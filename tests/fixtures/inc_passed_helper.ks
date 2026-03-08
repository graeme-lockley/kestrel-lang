export fun incPassed(s: { depth: Int, summaryOnly: Bool, counts: { passed: mut Int, failed: mut Int, startTime: mut Int } }): Unit = {
  s.counts.passed := s.counts.passed + 1;
  ()
}
