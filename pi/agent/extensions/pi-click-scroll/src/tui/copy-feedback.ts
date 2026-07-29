const COPY_STATUS_KEY = "pi-click-scroll:copy-status";
const COPY_STATUS_DURATION_MS = 2_000;

interface CopyFeedbackUi {
  setStatus(key: string, text: string | undefined): void;
}

export function createCopyFeedback(ui: CopyFeedbackUi) {
  let timeout: ReturnType<typeof setTimeout> | undefined;

  return {
    show(message: string): void {
      if (timeout !== undefined) clearTimeout(timeout);
      ui.setStatus(COPY_STATUS_KEY, message);
      timeout = setTimeout(() => {
        timeout = undefined;
        ui.setStatus(COPY_STATUS_KEY, undefined);
      }, COPY_STATUS_DURATION_MS);
    },
    clear(): void {
      if (timeout !== undefined) clearTimeout(timeout);
      timeout = undefined;
      ui.setStatus(COPY_STATUS_KEY, undefined);
    },
  };
}
