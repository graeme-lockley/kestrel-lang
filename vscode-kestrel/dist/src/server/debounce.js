"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DebouncedScheduler = void 0;
class DebouncedScheduler {
    delayMs;
    timer;
    constructor(delayMs) {
        this.delayMs = delayMs;
    }
    schedule(run) {
        if (this.timer != null) {
            clearTimeout(this.timer);
        }
        this.timer = setTimeout(() => {
            this.timer = undefined;
            void run();
        }, this.delayMs);
    }
    cancel() {
        if (this.timer != null) {
            clearTimeout(this.timer);
            this.timer = undefined;
        }
    }
}
exports.DebouncedScheduler = DebouncedScheduler;
//# sourceMappingURL=debounce.js.map