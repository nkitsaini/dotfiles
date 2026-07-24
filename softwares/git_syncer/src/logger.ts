import util from "util";
import { exec } from "child_process";
import {
  configure,
  getConsoleSink,
  getLogger,
  type LogRecord,
} from "@logtape/logtape";

export const logger = getLogger("app");
export enum LogLevel {
  debug = 0,
  trace = 1,
  info = 2,
  warning = 3,
  error = 4,
  fatal = 5,
}
export type Level = keyof typeof LogLevel;
export const LEVELS = Object.keys(LogLevel).filter((k) =>
  isNaN(Number(k)),
) as Level[];

const skipNotificationKey = "skip_notification"; // used to avoid infinite loop

// notify-send urgency, kept deliberately *separate* from the log level. Level
// decides whether something is surfaced at all (the notification threshold) and
// how it's logged; urgency decides how loud the desktop popup is. Previously
// every notifying record was sent as `critical`, so genuinely-actionable
// problems were indistinguishable from "your wifi blipped" — training the user
// to ignore all of them. Now `critical` is reserved for things that actually
// need the user to do something; recoverable/connectivity issues use `normal`.
export type NotifyUrgency = "low" | "normal" | "critical";

// Attach `{ [notifyUrgencyKey]: "normal" }` (etc.) to a log call's properties to
// override the urgency of its notification.
export const notifyUrgencyKey = "notify_urgency";

function urgencyForRecord(record: LogRecord): NotifyUrgency {
  const explicit = record.properties[notifyUrgencyKey];
  if (explicit === "low" || explicit === "normal" || explicit === "critical") {
    return explicit;
  }
  // Default: only a genuinely fatal condition is critical. A plain `error`
  // (e.g. a persistent-but-recoverable sync failure) notifies at normal.
  return LogLevel[record.level] >= LogLevel.fatal ? "critical" : "normal";
}

export async function configureLogging(
  minNotificationLevel: LogLevel = LogLevel.error,
) {
  await configure({
    sinks: {
      console: getConsoleSink({
        formatter(record: LogRecord): readonly unknown[] {
          return [record.rawMessage, record.properties];
        },
      }),
      notification: (record: LogRecord) => {
        if (LogLevel[record.level] < minNotificationLevel) {
          return;
        }
        if (record.properties[skipNotificationKey] === true) {
          return;
        }
        sendNotification(
          `Git Sync: ${record.level}`,
          JSON.stringify(record.message),
          urgencyForRecord(record),
        );
      },
    },
    loggers: [
      {
        category: "app",
        lowestLevel: "debug",
        sinks: ["console", "notification"],
      },
      {
        category: ["logtape", "meta"],
        sinks: [],
      },
    ],
  });
}

async function sendNotification(
  title: string,
  message: string,
  level: NotifyUrgency = "normal",
) {
  try {
    const execPromise = util.promisify(exec);
    const escapedTitle = title.replace(/"/g, '\\"');
    const escapedMessage = message.replace(/"/g, '\\"');
    await execPromise(
      `notify-send -u ${level} "${escapedTitle}" "${escapedMessage}"`,
    );
  } catch (e) {
    logger.error(`Failed to send notification: ${e} ${skipNotificationKey}`, {
      a: 7,
    });
  }
}
