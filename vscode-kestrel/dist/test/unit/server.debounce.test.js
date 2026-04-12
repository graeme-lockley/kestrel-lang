"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const debounce_1 = require("../../src/server/debounce");
(0, vitest_1.describe)('DebouncedScheduler', () => {
    (0, vitest_1.afterEach)(() => {
        vitest_1.vi.useRealTimers();
    });
    (0, vitest_1.it)('coalesces rapid schedules into a single run', async () => {
        vitest_1.vi.useFakeTimers();
        const scheduler = new debounce_1.DebouncedScheduler(25);
        const run = vitest_1.vi.fn(async () => Promise.resolve());
        scheduler.schedule(run);
        scheduler.schedule(run);
        scheduler.schedule(run);
        await vitest_1.vi.advanceTimersByTimeAsync(26);
        (0, vitest_1.expect)(run).toHaveBeenCalledTimes(1);
    });
    (0, vitest_1.it)('cancels pending run', async () => {
        vitest_1.vi.useFakeTimers();
        const scheduler = new debounce_1.DebouncedScheduler(25);
        const run = vitest_1.vi.fn(async () => Promise.resolve());
        scheduler.schedule(run);
        scheduler.cancel();
        await vitest_1.vi.advanceTimersByTimeAsync(26);
        (0, vitest_1.expect)(run).not.toHaveBeenCalled();
    });
});
//# sourceMappingURL=server.debounce.test.js.map