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
        if (LogLevel[record.level] >= minNotificationLevel) {
          let notificationLevel: "normal" | "critical" = "normal";
          if (record.properties[skipNotificationKey] === true) {
            return;
          }
          if (LogLevel[record.level] >= LogLevel.error) {
            notificationLevel = "critical";
          }
          sendNotification(
            `Git Sync: ${record.level}`,
            JSON.stringify(record.message),
            notificationLevel,
          );
        }
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
  level: "normal" | "critical" = "normal",
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
