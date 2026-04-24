//! Task combinators for asynchronous workflows.
//!
//! Provides mapping and coordination primitives (`map`, `all`, `race`) plus
//! cancellation and runtime async-flight introspection.
//!
//! ## Quick Start
//!
//! ```kestrel
//! import * as Task from "kestrel:sys/task"
//!
//! val both = await Task.all([taskA, taskB])
//! val first = await Task.race([taskA, taskB])
//! ```

export exception Cancelled

export extern fun map<A, B>(task: Task<A>, f: A -> B): Task<B> =
  jvm("kestrel.runtime.KTask#taskMap(java.lang.Object,java.lang.Object)")

export extern fun all<T>(tasks: List<Task<T>>): Task<List<T>> =
  jvm("kestrel.runtime.KTask#taskAll(java.lang.Object)")

export extern fun race<T>(tasks: List<Task<T>>): Task<T> =
  jvm("kestrel.runtime.KTask#taskRace(java.lang.Object)")

export extern fun cancel<T>(t: Task<T>): Unit =
  jvm("kestrel.runtime.KTask#cancel(java.lang.Object)")

export extern fun asyncTasksInFlight(): Int =
  jvm("kestrel.runtime.KRuntime#getAsyncTasksInFlight()")
