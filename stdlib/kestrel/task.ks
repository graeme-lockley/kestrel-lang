// kestrel:task — Task combinator stdlib module.
// Provides map, all, and race combinators for Task<T> values.

export fun map<A, B>(task: Task<A>, f: A -> B): Task<B> = __task_map(task, f)

export fun all<T>(tasks: List<Task<T>>): Task<List<T>> = __task_all(tasks)

export fun race<T>(tasks: List<Task<T>>): Task<T> = __task_race(tasks)
