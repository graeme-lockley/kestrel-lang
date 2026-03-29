export fun incPassed(
  s: {
    depth: Int,
    output: Int,
    counts: {
      passed: mut Int,
      failed: mut Int,
      startTime: mut Int,
      compactStackBox: mut { frames: List<List<String>> },
      compactExpanded: mut Bool
    }
  }
): Unit = {
  s.counts.passed := s.counts.passed + 1;
  ()
}
