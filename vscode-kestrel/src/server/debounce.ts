export class DebouncedScheduler {
  private timer: NodeJS.Timeout | undefined;

  constructor(private readonly delayMs: number) {}

  public schedule(run: () => Promise<void> | void): void {
    if (this.timer != null) {
      clearTimeout(this.timer);
    }
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void run();
    }, this.delayMs);
  }

  public cancel(): void {
    if (this.timer != null) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }
}
