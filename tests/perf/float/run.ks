import * as Basics from "kestrel:basics"
import * as Lst from "kestrel:list"
import * as Opt from "kestrel:option"
import * as Process from "kestrel:process"
import * as Str from "kestrel:string"

fun readArgInt(args: List<String>, index: Int, fallback: Int): Int =
  match (Lst.head(Lst.drop(args, index))) {
    None => fallback
    Some(s) => Opt.withDefault(Str.toInt(s), fallback)
  }

fun runWarmups(kestrelBin: String, scriptPath: String, warmups: Int): (Int, Int, Int) = {
  var i = 0
  var vmFailures = 0
  var jvmFailures = 0
  while (i < warmups) {
    val vmCode = Process.runProcess(kestrelBin, ["run", scriptPath]);
    val jvmCode = Process.runProcess(kestrelBin, ["run", "--target", "jvm", scriptPath]);

    if (vmCode != 0) {
      println("  warmup ${i + 1}: vm failed (exit ${vmCode})");
      vmFailures := vmFailures + 1
    } else {
      ()
    }
    if (jvmCode != 0) {
      println("  warmup ${i + 1}: jvm failed (exit ${jvmCode})");
      jvmFailures := jvmFailures + 1
    } else {
      ()
    }

    i := i + 1
    ()
  }
  (vmFailures, jvmFailures, vmFailures + jvmFailures)
}

fun runMeasured(name: String, kestrelBin: String, scriptPath: String, repeats: Int): (Int, Int, Int, Int, Int) = {
  var i = 0
  var vmMs = 0
  var jvmMs = 0
  var vmRuns = 0
  var jvmRuns = 0
  var failures = 0

  while (i < repeats) {
    val vmStart = Basics.nowMs();
    val vmCode = Process.runProcess(kestrelBin, ["run", scriptPath]);
    val vmElapsed = Basics.nowMs() - vmStart;
    if (vmCode == 0) {
      vmMs := vmMs + vmElapsed;
      vmRuns := vmRuns + 1;
      println("  run ${i + 1}: vm  ${vmElapsed}ms")
    } else {
      failures := failures + 1;
      println("  run ${i + 1}: vm  failed (exit ${vmCode})")
    }

    val jvmStart = Basics.nowMs();
    val jvmCode = Process.runProcess(kestrelBin, ["run", "--target", "jvm", scriptPath]);
    val jvmElapsed = Basics.nowMs() - jvmStart;
    if (jvmCode == 0) {
      jvmMs := jvmMs + jvmElapsed;
      jvmRuns := jvmRuns + 1;
      println("  run ${i + 1}: jvm ${jvmElapsed}ms")
    } else {
      failures := failures + 1;
      println("  run ${i + 1}: jvm failed (exit ${jvmCode})")
    }

    i := i + 1
    ()
  }

  val vmAvg = vmMs / (vmRuns + 1);
  val jvmAvg = jvmMs / (jvmRuns + 1);
  println("  summary ${name}:");
  println("    vm total ${vmMs}ms (${vmRuns} runs, avg ${vmAvg}ms)");
  println("    jvm total ${jvmMs}ms (${jvmRuns} runs, avg ${jvmAvg}ms)");
  println("    vm/jvm total ratio: ${vmMs * 100 / (jvmMs + 1)}%");
  (vmMs, jvmMs, vmRuns, jvmRuns, failures)
}

fun runWorkload(name: String, relPath: String, root: String, kestrelBin: String, repeats: Int, warmups: Int): (Int, Int, Int, Int, Int) = {
  val scriptPath = "${root}/${relPath}";
  println("");
  println("== ${name} ==");

  if (warmups > 0) {
    println("  warmups: ${warmups} (not measured)");
    val ws = runWarmups(kestrelBin, scriptPath, warmups);
    if (ws.2 > 0) {
      println("  warmup failures: ${ws.2}")
    } else {
      ()
    }
  } else {
    ()
  }

  println("  measured runs: ${repeats}");
  runMeasured(name, kestrelBin, scriptPath, repeats)
}

val proc = Process.getProcess()
val args = Lst.drop(proc.args, 2)
val repeats = readArgInt(args, 0, 3)
val warmups = readArgInt(args, 1, 1)
val safeRepeats = if (repeats <= 0) 1 else repeats
val safeWarmups = if (warmups < 0) 0 else warmups
val kestrelBin = "${proc.cwd}/kestrel"

println("Kestrel float performance harness")
println("cwd: ${proc.cwd}")
println("workloads: 4, repeats: ${safeRepeats}, warmups: ${safeWarmups}")

val started = Basics.nowMs();
val w1 = runWorkload("harmonic_series", "tests/perf/float/harmonic_series.ks", proc.cwd, kestrelBin, safeRepeats, safeWarmups);
val w2 = runWorkload("pi_integral", "tests/perf/float/pi_integral.ks", proc.cwd, kestrelBin, safeRepeats, safeWarmups);
val w3 = runWorkload("newton_sweep", "tests/perf/float/newton_sweep.ks", proc.cwd, kestrelBin, safeRepeats, safeWarmups);
val w4 = runWorkload("logistic_chaos", "tests/perf/float/logistic_chaos.ks", proc.cwd, kestrelBin, safeRepeats, safeWarmups);

val totalVmMs = w1.0 + w2.0 + w3.0 + w4.0;
val totalJvmMs = w1.1 + w2.1 + w3.1 + w4.1;
val totalVmRuns = w1.2 + w2.2 + w3.2 + w4.2;
val totalJvmRuns = w1.3 + w2.3 + w3.3 + w4.3;
val totalFailures = w1.4 + w2.4 + w3.4 + w4.4;
val vmDen = totalVmRuns + 1
val jvmDen = totalJvmRuns + 1
val ratioDen = totalJvmMs + 1
val totalVmAvg = totalVmMs / vmDen
val totalJvmAvg = totalJvmMs / jvmDen
val elapsed = Basics.nowMs() - started;

println("")
println("== overall summary ==")
println("vm total:  ${totalVmMs}ms (${totalVmRuns} runs, avg ${totalVmAvg}ms)")
println("jvm total: ${totalJvmMs}ms (${totalJvmRuns} runs, avg ${totalJvmAvg}ms)")
println("vm/jvm total ratio: ${totalVmMs * 100 / ratioDen}%")
println("failures: ${totalFailures}")
println("elapsed wall time: ${elapsed}ms")
