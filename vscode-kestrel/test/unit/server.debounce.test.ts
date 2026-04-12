import { afterEach, describe, expect, it, vi } from 'vitest';

import { DebouncedScheduler } from '../../src/server/debounce';

describe('DebouncedScheduler', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('coalesces rapid schedules into a single run', async () => {
    vi.useFakeTimers();

    const scheduler = new DebouncedScheduler(25);
    const run = vi.fn(async () => Promise.resolve());

    scheduler.schedule(run);
    scheduler.schedule(run);
    scheduler.schedule(run);

    await vi.advanceTimersByTimeAsync(26);

    expect(run).toHaveBeenCalledTimes(1);
  });

  it('cancels pending run', async () => {
    vi.useFakeTimers();

    const scheduler = new DebouncedScheduler(25);
    const run = vi.fn(async () => Promise.resolve());

    scheduler.schedule(run);
    scheduler.cancel();

    await vi.advanceTimersByTimeAsync(26);

    expect(run).not.toHaveBeenCalled();
  });
});
