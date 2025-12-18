import { Logger } from "tslog";
import util from "util";
import { exec } from "child_process";

export enum LogLevel {
  // eslint-disable-next-line @typescript-eslint/naming-convention
  SILLY = 0,
  // eslint-disable-next-line @typescript-eslint/naming-convention
  TRACE = 1,
  // eslint-disable-next-line @typescript-eslint/naming-convention
  DEBUG = 2,
  // eslint-disable-next-line @typescript-eslint/naming-convention
  INFO = 3,
  // eslint-disable-next-line @typescript-eslint/naming-convention
  WARN = 4,
  // eslint-disable-next-line @typescript-eslint/naming-convention
  ERROR = 5,
  // eslint-disable-next-line @typescript-eslint/naming-convention
  FATAL = 6,
}
export type Level = keyof typeof LogLevel;
export const LEVELS = Object.keys(LogLevel).filter((k) =>
  isNaN(Number(k)),
) as Level[];

export const logger = new Logger({});
const skipNotificationKey = "skip_notification";  // used to avoid infinite loop


export function attachNotificationTransport(level: LogLevel) {
  logger.attachTransport((log) => {
    // @ts-expect-error the typing for tslog is broken here
    if (skipNotificationKey in log && log[skipNotificationKey] == true) {
      return;
    }
    if (log["_meta"]["logLevelId"] < level) {
      return
    }

    let notificationLevel: "normal" | "critical" = "normal";
    if (log["_meta"]["logLevelId"] >= LogLevel.ERROR) {
      notificationLevel = "critical";
    }
    sendNotification(
      `Git Sync: ${log["_meta"]["logLevelName"]}`,
      JSON.stringify(log[0]),
      notificationLevel,
    );
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
    await execPromise(`notify-send -u ${level} "${escapedTitle}" "${escapedMessage}"`);
  } catch (e) {
    logger.log(
      LogLevel.ERROR,
      LEVELS[LogLevel.ERROR],
      "Failed to send notification:",
      e,
      { [skipNotificationKey]: true },
    );
  }
}
