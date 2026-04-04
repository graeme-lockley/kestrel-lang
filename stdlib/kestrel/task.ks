// kestrel:task — Task combinator stdlib module.
// Provides map, all, race, and cancel API for Task<T> values.

export exception Cancelled

export fun map<A, B>(task: Task<A>, f: A -> B): Task<B> = __task_map(task, f)

export fun all<T>(tasks: List<Task<T>>): Task<List<T>> = __task_all(tasks)

export fun race<T>(tasks: List<Task<T>>): Task<T> = __task_race(tasks)

export fun cancel<T>(t: Task<T>): Unit = __task_cancel(t)
