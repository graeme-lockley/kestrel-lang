export fun getProcess(): P = {
  val os = __get_os();
  val a = __get_args();
  val c = __get_cwd();
  { os = os, args = a, env = [], cwd = c }
}

export fun runProcess(program: String, args: List<String>): Int = __run_process(program, args)
