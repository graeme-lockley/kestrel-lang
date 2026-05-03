#!/usr/bin/env tsx
/**
 * implement-kanban-stories.ts
 *
 * A deterministic state-machine runner around badlogic/pi-mono.
 *
 * Intent:
 *   - The runner owns orchestration, state, retry limits, tests, lint, and Kanban movement.
 *   - Pi owns the non-deterministic LLM work: planning, building, fixing, and semantic verification.
 *   - Each story gets a shared Pi session, while each phase is a separate Pi invocation.
 *
 * Expected layout:
 *
 *   .github/
 *     skills/
 *       plan-story/SKILL.md
 *       build-story/SKILL.md
 *       verify-story/SKILL.md  (not yet present; supply via --verify-skill)
 *
 *   .pi/
 *     runs/
 *
 *   docs/
 *     kanban/
 *       unplanned/
 *       done/
 *       blocked/
 *
 * Usage:
 *
 *   npx tsx scripts/implement-kanban-stories.ts
 *
 * Or:
 *
 *   npx tsx scripts/implement-kanban-stories.ts \
 *     --story-dir ./docs/kanban/unplanned \
 *     --limit 1 \
 *     --done-dir ./docs/kanban/done \
 *     --blocked-dir ./docs/kanban/blocked \
 *     --test "./scripts/test-all.sh" \
 *     --lint "./scripts/lint-all.sh" \
 *     --max-attempts 8
 *
 * Notes:
 *   - This uses the Pi CLI in print mode.
 *   - It uses --session <path> so plan/build/verify share a story-specific Pi session.
 *   - If your installed Pi version requires an existing session file before --session can be used,
 *     create the session interactively once, or adapt buildPiArgs() to use --continue / --fork / RPC.
 */

import { spawn } from "node:child_process";
import {
  access,
  mkdir,
  readdir,
  readFile,
  rename,
  stat,
  writeFile,
} from "node:fs/promises";
import path from "node:path";
import process from "node:process";

type Phase =
  | "DISCOVER_STORIES"
  | "START_STORY"
  | "PLAN_STORY"
  | "EVALUATE_PLAN"
  | "VERIFY_PLAN"
  | "COMMIT_PLAN"
  | "BUILD_STORY"
  | "EVALUATE_BUILD"
  | "RUN_TESTS"
  | "EVALUATE_TESTS"
  | "RUN_LINT"
  | "EVALUATE_LINT"
  | "VERIFY_STORY"
  | "EVALUATE_VERIFY"
  | "MARK_DONE"
  | "MARK_BLOCKED"
  | "NEXT_STORY"
  | "FINISHED"
  | "FAILED";

type PiStatus = "success" | "issue";

interface Config {
  piCommand: string;
  rootDir: string;
  storyDir: string;
  doneDir: string;
  blockedDir: string;
  runDirBase: string;
  sessionDir: string;
  planSkillPath: string;
  buildSkillPath: string;
  verifySkillPath: string;
  limit?: number;
  maxAttempts: number;
  testCommand: string;
  lintCommand: string;
  piTimeoutMs: number;
  testTimeoutMs: number;
  storyPattern: RegExp;
  continueOnBlocked: boolean;
  dryRun: boolean;
  verbose: boolean;
  piModel?: string;
  piProvider?: string;
  piThinking?: string;
}

interface CommandResult {
  command: string;
  exitCode: number | null;
  stdout: string;
  stderr: string;
  durationMs: number;
  timedOut?: boolean;
}

interface PiInvocationResult extends CommandResult {
  parsed: unknown | null;
  rawJsonText: string | null;
}

interface PlanResult {
  status: PiStatus;
  summary?: string;
  reason?: string | null;
  acceptanceCriteria?: string[];
  implementationPlan?: string[];
  filesLikelyToChange?: string[];
  risks?: string[];
}

interface BuildResult {
  status: PiStatus;
  summary?: string;
  reason?: string | null;
  filesChanged?: string[];
  issues?: string[];
}

interface VerifyResult {
  status: PiStatus;
  summary?: string;
  reason?: string | null;
  issues?: string[];
  criteriaResults?: Array<{
    criterion: string;
    met: boolean;
    evidence?: string;
    issue?: string | null;
  }>;
}

interface StoryContext {
  originalStoryPath: string;
  storyPath: string;
  storyId: string;
  storyRunDir: string;
  sessionPath: string;
  attempt: number;
  planRepairAttempts: number;
  artifactSequence: number;
  planJsonPath?: string;
  buildJsonPath?: string;
  testJsonPath?: string;
  lintJsonPath?: string;
  verifyJsonPath?: string;
  issues: string[];
  blockedReason?: string;
  plan?: PlanResult;
  build?: BuildResult;
  verify?: VerifyResult;
  testResult?: CommandResult;
  lintResult?: CommandResult;
}

interface Machine {
  phase: Phase;
  config: Config;
  runId: string;
  runDir: string;
  stories: string[];
  storyIndex: number;
  current?: StoryContext;
  failure?: string;
}

interface PlanVerificationResult {
  ok: boolean;
  plannedStoryPath: string;
  gitStatus: CommandResult;
  reasons: string[];
}

type LogLevel = "info" | "success" | "error";

const ANSI = {
  reset: "\x1b[0m",
  grey: "\x1b[90m",
  green: "\x1b[32m",
  red: "\x1b[31m",
} as const;

const DEFAULT_CONFIG: Config = {
  piCommand: "pi",
  rootDir: process.cwd(),
  storyDir: "./docs/kanban/unplanned",
  doneDir: "./docs/kanban/done",
  blockedDir: "./docs/kanban/blocked",
  runDirBase: ".pi/runs",
  sessionDir: ".pi/story-sessions",
  planSkillPath: ".github/skills/plan-story/SKILL.md",
  buildSkillPath: ".github/skills/build-story/SKILL.md",
  verifySkillPath: ".github/skills/verify-story/SKILL.md",
  limit: undefined,
  maxAttempts: 8,
  testCommand: "./scripts/test-all.sh",
  lintCommand: "./scripts/lint-all.sh",
  piTimeoutMs: 10 * 60 * 1000,
  testTimeoutMs: 10 * 60 * 1000,
  storyPattern: /\.md$/i,
  continueOnBlocked: false,
  dryRun: false,
  verbose: true,
};

async function main(): Promise<void> {
  const config = parseArgs(process.argv.slice(2));
  const runId = timestampForPath(new Date());
  const runDir = path.resolve(config.rootDir, config.runDirBase, runId);

  const machine: Machine = {
    phase: "DISCOVER_STORIES",
    config,
    runId,
    runDir,
    stories: [],
    storyIndex: 0,
  };

  await ensureRuntimeDirectories(machine);

  // Phases that emit their own console output via Pi heartbeats — skip the redundant banner.
  const silentPhases = new Set<string>(["PLAN_STORY", "BUILD_STORY", "VERIFY_STORY"]);

  while (machine.phase !== "FINISHED" && machine.phase !== "FAILED") {
    await journal(machine, {
      event: "phase.entered",
      phase: machine.phase,
      story: machine.current?.storyPath ?? null,
      attempt: machine.current?.attempt ?? null,
    });

    if (!silentPhases.has(machine.phase)) {
      const storyId = machine.current?.storyId ?? null;
      const label = storyId ? `${machine.phase} ${storyId}` : machine.phase;
      log(machine, label);
    }

    await transition(machine);
  }

  await journal(machine, {
    event: "run.completed",
    phase: machine.phase,
    failure: machine.failure ?? null,
  });

  if (machine.phase === "FAILED") {
    throw new Error(machine.failure ?? "Workflow failed");
  }

  log(machine, `Workflow finished. Run directory: ${machine.runDir}`);
}

async function transition(machine: Machine): Promise<void> {
  switch (machine.phase) {
    case "DISCOVER_STORIES":
      return discoverStories(machine);

    case "START_STORY":
      return startStory(machine);

    case "PLAN_STORY":
      return planStory(machine);

    case "EVALUATE_PLAN":
      return evaluatePlan(machine);

    case "VERIFY_PLAN":
      return verifyPlan(machine);

    case "COMMIT_PLAN":
      return commitPlan(machine);

    case "BUILD_STORY":
      return buildStory(machine);

    case "EVALUATE_BUILD":
      return evaluateBuild(machine);

    case "RUN_TESTS":
      return runTests(machine);

    case "EVALUATE_TESTS":
      return evaluateTests(machine);

    case "RUN_LINT":
      return runLint(machine);

    case "EVALUATE_LINT":
      return evaluateLint(machine);

    case "VERIFY_STORY":
      return verifyStory(machine);

    case "EVALUATE_VERIFY":
      return evaluateVerify(machine);

    case "MARK_DONE":
      return markDone(machine);

    case "MARK_BLOCKED":
      return markBlocked(machine);

    case "NEXT_STORY":
      return nextStory(machine);

    case "FINISHED":
    case "FAILED":
      return;

    default: {
      const unreachable: never = machine.phase;
      throw new Error(`Unhandled phase: ${unreachable}`);
    }
  }
}

async function discoverStories(machine: Machine): Promise<void> {
  const storyDir = resolveFromRoot(machine.config, machine.config.storyDir);
  const entries = await readdir(storyDir, { withFileTypes: true });

  machine.stories = entries
    .filter((entry) => entry.isFile())
    .map((entry) => path.join(storyDir, entry.name))
    .filter((file) => machine.config.storyPattern.test(file))
    .sort();

  if (typeof machine.config.limit === "number") {
    machine.stories = machine.stories.slice(0, machine.config.limit);
  }

  await journal(machine, {
    event: "stories.discovered",
    count: machine.stories.length,
    stories: machine.stories,
  });

  machine.phase = machine.stories.length === 0 ? "FINISHED" : "START_STORY";
}

async function startStory(machine: Machine): Promise<void> {
  const storyPath = machine.stories[machine.storyIndex];

  if (!storyPath) {
    machine.phase = "FINISHED";
    return;
  }

  const storyId = safeName(path.basename(storyPath, path.extname(storyPath)));
  const storyRunDir = path.join(machine.runDir, storyId);
  const sessionPath = path.resolve(
    machine.config.rootDir,
    machine.config.sessionDir,
    `${storyId}.jsonl`,
  );

  await mkdir(storyRunDir, { recursive: true });
  await mkdir(path.dirname(sessionPath), { recursive: true });

  machine.current = {
    originalStoryPath: storyPath,
    storyPath,
    storyId,
    storyRunDir,
    sessionPath,
    attempt: 1,
    planRepairAttempts: 0,
    artifactSequence: 0,
    issues: [],
  };

  await writeStoryState(machine);
  log(machine, `Starting story ${machine.storyIndex + 1}/${machine.stories.length}: ${storyPath}`);

  machine.phase = "PLAN_STORY";
}

async function planStory(machine: Machine): Promise<void> {
  const story = requireStory(machine);

  const prompt = buildPlanPrompt(story);
  await writeFile(nextStoryArtifactPath(story, "plan.prompt.md"), prompt, "utf8");

  const planRawPath = nextStoryArtifactPath(story, "plan.raw.txt");

  const result = await invokePi(machine, {
    phaseName: "PLAN",
    skillPath: machine.config.planSkillPath,
    tools: ["read", "grep", "find", "ls", "write", "bash"],
    files: [story.storyPath],
    message: prompt,
    outputPath: planRawPath,
  });

  await writeJson(nextStoryArtifactPath(story, "plan.invocation.json"), result);
  story.plan = coercePlanResult(result.parsed);
  story.planJsonPath = nextStoryArtifactPath(story, "plan.json");
  await writeJson(story.planJsonPath, story.plan);
  await writeStoryState(machine);

  machine.phase = "EVALUATE_PLAN";
}

async function evaluatePlan(machine: Machine): Promise<void> {
  const story = requireStory(machine);

  if (!story.plan) {
    story.blockedReason = "Planning did not produce a valid result.";
    machine.phase = "MARK_BLOCKED";
    return;
  }

  if (story.plan.status === "issue") {
    story.blockedReason = story.plan.reason ?? "Planning reported an issue.";
    machine.phase = "MARK_BLOCKED";
    return;
  }

  machine.phase = "VERIFY_PLAN";
}

async function verifyPlan(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const plannedStoryPath = resolveExpectedPlannedStoryPath(machine, story);

  if (machine.config.dryRun) {
    story.storyPath = plannedStoryPath;
    story.issues = [];
    machine.phase = "COMMIT_PLAN";
    return;
  }

  const oldStoryPath = path.resolve(story.storyPath);
  const plannedExists = await fileExists(plannedStoryPath);
  const oldStillExists = await fileExists(oldStoryPath);
  const gitStatus = await runShell("git status --porcelain", machine.config.rootDir);
  const reasons: string[] = [];

  if (!plannedExists) {
    reasons.push(`Planned story file does not exist: ${plannedStoryPath}`);
  }

  if (oldStillExists) {
    reasons.push(`Original story file still exists (story was not moved): ${oldStoryPath}`);
  }

  if (gitStatus.exitCode !== 0) {
    reasons.push(`git status failed with exit code ${gitStatus.exitCode}`);
  }

  if (gitStatus.exitCode === 0) {
    const changedPaths = parseGitStatusPaths(gitStatus.stdout).map((changedPath) =>
      toRepoRelativePosix(machine.config.rootDir, path.resolve(machine.config.rootDir, changedPath)),
    );

    const oldRelative = toRepoRelativePosix(machine.config.rootDir, oldStoryPath);
    const plannedRelative = toRepoRelativePosix(machine.config.rootDir, plannedStoryPath);
    const allowed = new Set<string>([oldRelative, plannedRelative]);

    const unexpected = changedPaths.filter((changedPath) => !allowed.has(changedPath));
    if (unexpected.length > 0) {
      reasons.push(
        `Unexpected changed paths after planning: ${unexpected.join(", ")}. Only the story move is allowed.`,
      );
    }

    const hasOldPathChange = changedPaths.includes(oldRelative);
    const hasPlannedPathChange = changedPaths.includes(plannedRelative);

    if (!hasOldPathChange || !hasPlannedPathChange) {
      reasons.push(
        `git status must show both paths for the move: deleted ${oldRelative} and added ${plannedRelative}.`,
      );
    }
  }

  const verification: PlanVerificationResult = {
    ok: reasons.length === 0,
    plannedStoryPath,
    gitStatus,
    reasons,
  };

  await writeJson(
    nextStoryArtifactPath(story, `plan-verify-${story.planRepairAttempts + 1}.json`),
    verification,
  );

  if (verification.ok) {
    story.storyPath = plannedStoryPath;
    story.issues = [];
    machine.phase = "COMMIT_PLAN";
    return;
  }

  story.planRepairAttempts += 1;
  story.issues = [
    "Deterministic plan verification failed.",
    ...verification.reasons,
    "Repair required: only the story file may change. Move it to planned and undo any other edits.",
  ];
  machine.phase = "PLAN_STORY";
}

async function commitPlan(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const currentStoryPath = path.resolve(story.storyPath);
  const originalStoryPath = path.resolve(story.originalStoryPath);

  if (!machine.config.dryRun) {
    const currentStoryRelative = toRepoRelativePosix(machine.config.rootDir, currentStoryPath);
    const originalStoryRelative = toRepoRelativePosix(machine.config.rootDir, originalStoryPath);
    const addResult = await runCommand(
      "git",
      ["add", "-A", "--", originalStoryRelative, currentStoryRelative],
      machine.config.rootDir,
    );

    if (addResult.exitCode !== 0) {
      story.blockedReason =
        `Failed to stage planned story during commit phase. Exit code ${addResult.exitCode}.`;
      machine.phase = "MARK_BLOCKED";
      return;
    }

    const commitMessage = `docs(kanban): move ${story.storyId} to planned`;
    const commitResult = await runCommand(
      "git",
      ["commit", "-m", commitMessage],
      machine.config.rootDir,
    );

    if (commitResult.exitCode !== 0) {
      story.blockedReason =
        `Failed to commit planned story during commit phase. Exit code ${commitResult.exitCode}.`;
      machine.phase = "MARK_BLOCKED";
      return;
    }
  }

  machine.phase = "BUILD_STORY";
}

async function buildStory(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const planPath = story.planJsonPath;

  if (!planPath) {
    story.blockedReason = "Invariant violated: missing plan JSON artifact before build.";
    machine.phase = "MARK_BLOCKED";
    return;
  }

  const issuesPath = nextStoryArtifactPath(story, `issues-${story.attempt}.md`);
  const prompt = buildBuildPrompt(story);

  await writeFile(issuesPath, renderIssues(story.issues), "utf8");
  await writeFile(nextStoryArtifactPath(story, `build-${story.attempt}.prompt.md`), prompt, "utf8");

  const buildRawPath = nextStoryArtifactPath(story, `build-${story.attempt}.raw.txt`);

  const result = await invokePi(machine, {
    phaseName: "BUILD",
    skillPath: machine.config.buildSkillPath,
    tools: ["read", "grep", "find", "ls", "edit", "write", "bash"],
    files: [story.storyPath, planPath, issuesPath],
    message: prompt,
    outputPath: buildRawPath,
  });

  await writeJson(nextStoryArtifactPath(story, `build-${story.attempt}.invocation.json`), result);
  story.build = coerceBuildResult(result.parsed);
  story.buildJsonPath = nextStoryArtifactPath(story, `build-${story.attempt}.json`);
  await writeJson(story.buildJsonPath, story.build);
  await writeStoryState(machine);

  machine.phase = "EVALUATE_BUILD";
}

async function evaluateBuild(machine: Machine): Promise<void> {
  const story = requireStory(machine);

  if (!story.build) {
    story.blockedReason = `Build attempt ${story.attempt} did not produce a valid result.`;
    machine.phase = "MARK_BLOCKED";
    return;
  }

  if (story.build.status === "issue") {
    story.blockedReason =
      story.build.reason ?? `Build attempt ${story.attempt} reported an issue.`;
    machine.phase = "MARK_BLOCKED";
    return;
  }

  machine.phase = "RUN_TESTS";
}

async function runTests(machine: Machine): Promise<void> {
  const story = requireStory(machine);

  if (!story.build || story.build.status !== "success") {
    story.blockedReason =
      "Invariant violated: RUN_TESTS reached before a successful build.";
    log(machine, story.blockedReason, "error");
    machine.phase = "MARK_BLOCKED";
    return;
  }

  log(
    machine,
    `Running post-build tests for ${story.storyId}, attempt ${story.attempt}`,
  );

  story.testResult = machine.config.dryRun
    ? dryRunCommand(machine.config.testCommand)
    : await runShell(machine.config.testCommand, machine.config.rootDir, {
        streamOutput: true,
        timeoutMs: machine.config.testTimeoutMs,
      });

  story.testJsonPath = nextStoryArtifactPath(story, `test-${story.attempt}.json`);
  await writeJson(story.testJsonPath, story.testResult);
  await writeFile(
    nextStoryArtifactPath(story, `test-${story.attempt}.stdout.log`),
    story.testResult.stdout,
    "utf8",
  );
  await writeFile(
    nextStoryArtifactPath(story, `test-${story.attempt}.stderr.log`),
    story.testResult.stderr,
    "utf8",
  );
  await writeStoryState(machine);

  machine.phase = "EVALUATE_TESTS";
}

async function evaluateTests(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const result = story.testResult;

  if (!result) {
    story.blockedReason = "Test command did not produce a result.";
    machine.phase = "MARK_BLOCKED";
    return;
  }

  if (result.exitCode !== 0) {
    log(machine, `Tests failed for ${story.storyId} (attempt ${story.attempt}).`, "error");
    story.issues = [
      `Tests failed on attempt ${story.attempt}.`,
      `Command: ${result.command}`,
      `Exit code: ${result.exitCode}`,
      "STDOUT:",
      truncate(result.stdout, 12000),
      "STDERR:",
      truncate(result.stderr, 12000),
    ];
    machine.phase = nextAttemptOrBlocked(machine, "Tests failed.");
    return;
  }

  log(machine, `Tests passed for ${story.storyId} (attempt ${story.attempt}).`, "success");

  machine.phase = "RUN_LINT";
}

async function runLint(machine: Machine): Promise<void> {
  const story = requireStory(machine);

  if (!story.build || story.build.status !== "success") {
    story.blockedReason =
      "Invariant violated: RUN_LINT reached before a successful build.";
    log(machine, story.blockedReason, "error");
    machine.phase = "MARK_BLOCKED";
    return;
  }

  log(
    machine,
    `Running post-build lint for ${story.storyId}, attempt ${story.attempt}`,
  );

  story.lintResult = machine.config.dryRun
    ? dryRunCommand(machine.config.lintCommand)
    : await runShell(machine.config.lintCommand, machine.config.rootDir, {
        streamOutput: true,
        timeoutMs: machine.config.testTimeoutMs,
      });

  story.lintJsonPath = nextStoryArtifactPath(story, `lint-${story.attempt}.json`);
  await writeJson(story.lintJsonPath, story.lintResult);
  await writeFile(
    nextStoryArtifactPath(story, `lint-${story.attempt}.stdout.log`),
    story.lintResult.stdout,
    "utf8",
  );
  await writeFile(
    nextStoryArtifactPath(story, `lint-${story.attempt}.stderr.log`),
    story.lintResult.stderr,
    "utf8",
  );
  await writeStoryState(machine);

  machine.phase = "EVALUATE_LINT";
}

async function evaluateLint(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const result = story.lintResult;

  if (!result) {
    story.blockedReason = "Lint command did not produce a result.";
    machine.phase = "MARK_BLOCKED";
    return;
  }

  if (result.exitCode !== 0) {
    log(machine, `Lint failed for ${story.storyId} (attempt ${story.attempt}).`, "error");
    story.issues = [
      `Lint failed on attempt ${story.attempt}.`,
      `Command: ${result.command}`,
      `Exit code: ${result.exitCode}`,
      "STDOUT:",
      truncate(result.stdout, 12000),
      "STDERR:",
      truncate(result.stderr, 12000),
    ];
    machine.phase = nextAttemptOrBlocked(machine, "Lint failed.");
    return;
  }

  log(machine, `Lint passed for ${story.storyId} (attempt ${story.attempt}).`, "success");

  machine.phase = "VERIFY_STORY";
}

async function verifyStory(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const planPath = story.planJsonPath;
  const buildPath = story.buildJsonPath;
  const testPath = story.testJsonPath;
  const lintPath = story.lintJsonPath;

  if (!planPath || !buildPath || !testPath || !lintPath) {
    story.blockedReason = "Invariant violated: missing plan/build/test/lint artifacts before verify.";
    machine.phase = "MARK_BLOCKED";
    return;
  }

  const prompt = buildVerifyPrompt(story);
  await writeFile(nextStoryArtifactPath(story, `verify-${story.attempt}.prompt.md`), prompt, "utf8");

  const verifyRawPath = nextStoryArtifactPath(story, `verify-${story.attempt}.raw.txt`);

  const result = await invokePi(machine, {
    phaseName: "VERIFY",
    skillPath: machine.config.verifySkillPath,
    tools: ["read", "grep", "find", "ls"],
    files: [story.storyPath, planPath, buildPath, testPath, lintPath],
    message: prompt,
    outputPath: verifyRawPath,
  });

  await writeJson(nextStoryArtifactPath(story, `verify-${story.attempt}.invocation.json`), result);
  story.verify = coerceVerifyResult(result.parsed);
  story.verifyJsonPath = nextStoryArtifactPath(story, `verify-${story.attempt}.json`);
  await writeJson(story.verifyJsonPath, story.verify);
  await writeStoryState(machine);

  machine.phase = "EVALUATE_VERIFY";
}

async function evaluateVerify(machine: Machine): Promise<void> {
  const story = requireStory(machine);

  if (!story.verify) {
    story.issues = [`Verification attempt ${story.attempt} did not produce a valid result.`];
    machine.phase = nextAttemptOrBlocked(machine, "Verification produced invalid output.");
    return;
  }

  if (story.verify.status === "success") {
    log(machine, `Verification passed for ${story.storyId}.`, "success");
    machine.phase = "MARK_DONE";
    return;
  }

  log(machine, `Verification failed for ${story.storyId} (attempt ${story.attempt}).`, "error");

  story.issues = [
    `Verification failed on attempt ${story.attempt}.`,
    story.verify.reason ?? story.verify.summary ?? "No reason supplied.",
    ...(story.verify.issues ?? []),
  ];

  machine.phase = nextAttemptOrBlocked(machine, "Verification failed.");
}

async function markDone(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const doneDir = resolveFromRoot(machine.config, machine.config.doneDir);
  const targetPath = path.join(doneDir, path.basename(story.storyPath));

  await mkdir(doneDir, { recursive: true });

  if (!machine.config.dryRun) {
    await rename(story.storyPath, targetPath);
    await runShell(
      `git add -A && git commit -m "docs(kanban): move ${story.storyId} to done"`,
      machine.config.rootDir,
    );
  }

  await writeFile(
    nextStoryArtifactPath(story, "final-report.md"),
    renderFinalReport(machine, story, "done"),
    "utf8",
  );

  await journal(machine, {
    event: "story.done",
    story: story.storyPath,
    targetPath,
    attempts: story.attempt,
  });

  log(machine, `Done: ${story.storyPath}`, "success");
  machine.phase = "NEXT_STORY";
}

async function markBlocked(machine: Machine): Promise<void> {
  const story = requireStory(machine);
  const blockedDir = resolveFromRoot(machine.config, machine.config.blockedDir);
  const targetPath = path.join(blockedDir, path.basename(story.storyPath));

  await mkdir(blockedDir, { recursive: true });

  const reason =
    story.blockedReason ??
    story.issues.join("\n") ??
    "Story blocked for unspecified reason.";

  story.blockedReason = reason;

  await writeFile(
    nextStoryArtifactPath(story, "final-report.md"),
    renderFinalReport(machine, story, "blocked"),
    "utf8",
  );

  if (!machine.config.dryRun) {
    await rename(story.storyPath, targetPath);
    await runShell(
      `git add -A && git commit -m "docs(kanban): move ${story.storyId} to blocked"`,
      machine.config.rootDir,
    );
  }

  await journal(machine, {
    event: "story.blocked",
    story: story.storyPath,
    targetPath,
    attempts: story.attempt,
    reason,
  });

  log(machine, `Blocked: ${story.storyPath}`, "error");
  log(machine, `Reason: ${reason}`, "error");

  if (machine.config.continueOnBlocked) {
    machine.phase = "NEXT_STORY";
  } else {
    machine.failure = `Blocked story: ${story.storyPath}\n${reason}`;
    machine.phase = "FAILED";
  }
}

async function nextStory(machine: Machine): Promise<void> {
  machine.storyIndex += 1;
  machine.current = undefined;
  machine.phase = machine.storyIndex >= machine.stories.length ? "FINISHED" : "START_STORY";
}

function nextAttemptOrBlocked(machine: Machine, blockedReason: string): Phase {
  const story = requireStory(machine);

  if (story.attempt >= machine.config.maxAttempts) {
    story.blockedReason = `${blockedReason} Reached max attempts: ${machine.config.maxAttempts}.`;
    return "MARK_BLOCKED";
  }

  story.attempt += 1;
  return "BUILD_STORY";
}

interface PiInvocationOptions {
  phaseName: "PLAN" | "BUILD" | "VERIFY";
  skillPath: string;
  tools: string[];
  files: string[];
  message: string;
  outputPath: string;
}

async function invokePi(
  machine: Machine,
  options: PiInvocationOptions,
): Promise<PiInvocationResult> {
  const story = requireStory(machine);
  const args = buildPiArgs(machine, options);
  const phaseLog =
    options.phaseName === "VERIFY"
      ? `Invoking Pi for VERIFY: ${story.storyId} (checking implementation against acceptance criteria using story, plan, build, test, and lint artifacts)`
      : `Invoking Pi for ${options.phaseName}: ${story.storyId}`;
  const heartbeatLabel =
    options.phaseName === "VERIFY"
      ? `VERIFY ${story.storyId} (acceptance criteria + test/lint validation)`
      : `${options.phaseName} ${story.storyId}`;

  log(machine, phaseLog);

  const result = machine.config.dryRun
    ? dryRunPi(options)
    : await runCommand(machine.config.piCommand, args, machine.config.rootDir, {
        streamOutput: true,
        heartbeatLabel,
        heartbeatMs: 15000,
        timeoutMs: machine.config.piTimeoutMs,
      });

  if (result.timedOut) {
    throw new Error(
      `Pi invocation timed out after ${machine.config.piTimeoutMs / 1000}s during ${options.phaseName} for ${story.storyId}. Aborting run.`,
    );
  }

  await writeFile(options.outputPath, result.stdout, "utf8");

  const rawJsonText = extractJsonObject(result.stdout);
  let parsed: unknown | null = null;

  if (rawJsonText) {
    try {
      parsed = JSON.parse(rawJsonText);
    } catch {
      parsed = null;
    }
  }

  if (result.exitCode !== 0) {
    throw new Error(
      `Pi invocation failed during ${options.phaseName} for ${story.storyId}.\n` +
        `Command: ${machine.config.piCommand} ${args.join(" ")}\n` +
        `Exit code: ${result.exitCode}\n` +
        `STDERR:\n${result.stderr}`,
    );
  }

  return {
    ...result,
    parsed,
    rawJsonText,
  };
}

function buildPiArgs(machine: Machine, options: PiInvocationOptions): string[] {
  const story = requireStory(machine);

  const args: string[] = [
    "--print",
    "--session-dir",
    resolveFromRoot(machine.config, machine.config.sessionDir),
    "--session",
    story.sessionPath,
    "--no-skills",
    "--skill",
    resolveFromRoot(machine.config, options.skillPath),
    "--tools",
    options.tools.join(","),
  ];

  if (machine.config.piProvider) {
    args.push("--provider", machine.config.piProvider);
  }

  if (machine.config.piModel) {
    args.push("--model", machine.config.piModel);
  }

  if (machine.config.piThinking) {
    args.push("--thinking", machine.config.piThinking);
  }

  for (const file of options.files) {
    args.push(`@${path.resolve(machine.config.rootDir, file)}`);
  }

  args.push(options.message);

  return args;
}

async function runCommand(
  command: string,
  args: string[],
  cwd: string,
  options?: {
    streamOutput?: boolean;
    heartbeatLabel?: string;
    heartbeatMs?: number;
    timeoutMs?: number;
  },
): Promise<CommandResult> {
  const started = Date.now();
  const streamOutput = options?.streamOutput ?? false;
  const heartbeatLabel = options?.heartbeatLabel;
  const heartbeatMs = options?.heartbeatMs ?? 0;
  const timeoutMs = options?.timeoutMs;

  return new Promise((resolve) => {
    const child = spawn(command, args, {
      cwd,
      shell: false,
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    });

    let stdout = "";
    let stderr = "";
    let heartbeatTimer: NodeJS.Timeout | undefined;
    let timeoutTimer: NodeJS.Timeout | undefined;
    let timedOut = false;

    if (streamOutput && heartbeatLabel && heartbeatMs > 0) {
      heartbeatTimer = setInterval(() => {
        const seconds = Math.floor((Date.now() - started) / 1000);
        writeRunnerLine(
          `${heartbeatLabel} still running (${seconds}s elapsed)`,
          "info",
          "stderr",
        );
      }, heartbeatMs);
    }

    if (timeoutMs && timeoutMs > 0) {
      timeoutTimer = setTimeout(() => {
        timedOut = true;
        writeRunnerLine(
          `Command timed out after ${timeoutMs / 1000}s, killing: ${command}`,
          "error",
          "stderr",
        );
        child.kill("SIGTERM");
        setTimeout(() => { child.kill("SIGKILL"); }, 5000);
      }, timeoutMs);
    }

    const clearTimers = () => {
      if (heartbeatTimer) {
        clearInterval(heartbeatTimer);
        heartbeatTimer = undefined;
      }
      if (timeoutTimer) {
        clearTimeout(timeoutTimer);
        timeoutTimer = undefined;
      }
    };

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
      if (streamOutput) {
        process.stdout.write(chunk);
      }
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
      if (streamOutput) {
        process.stderr.write(chunk);
      }
    });

    child.on("close", (exitCode) => {
      clearTimers();
      resolve({
        command: [command, ...args].join(" "),
        exitCode,
        stdout,
        stderr: timedOut ? `${stderr}\nTIMEOUT: command exceeded ${timeoutMs}ms` : stderr,
        durationMs: Date.now() - started,
        timedOut,
      });
    });

    child.on("error", (error) => {
      clearTimers();
      resolve({
        command: [command, ...args].join(" "),
        exitCode: -1,
        stdout,
        stderr: `${stderr}\n${String(error)}`,
        durationMs: Date.now() - started,
      });
    });
  });
}

async function runShellWithOptions(
  command: string,
  cwd: string,
  options: { streamOutput: boolean; started?: number; timeoutMs?: number },
): Promise<CommandResult> {
  const started = options.started ?? Date.now();
  const streamOutput = options.streamOutput;
  const timeoutMs = options.timeoutMs;

  return new Promise((resolve) => {
    const child = spawn(command, {
      cwd,
      shell: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    });

    let stdout = "";
    let stderr = "";
    let timeoutTimer: NodeJS.Timeout | undefined;
    let timedOut = false;

    if (timeoutMs && timeoutMs > 0) {
      timeoutTimer = setTimeout(() => {
        timedOut = true;
        writeRunnerLine(
          `Command timed out after ${timeoutMs / 1000}s, killing: ${command}`,
          "error",
          "stderr",
        );
        child.kill("SIGTERM");
        setTimeout(() => { child.kill("SIGKILL"); }, 5000);
      }, timeoutMs);
    }

    const clearTimers = () => {
      if (timeoutTimer) {
        clearTimeout(timeoutTimer);
        timeoutTimer = undefined;
      }
    };

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
      if (streamOutput) {
        process.stdout.write(chunk);
      }
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
      if (streamOutput) {
        process.stderr.write(chunk);
      }
    });

    child.on("close", (exitCode) => {
      clearTimers();
      resolve({
        command,
        exitCode,
        stdout,
        stderr: timedOut ? `${stderr}\nTIMEOUT: command exceeded ${timeoutMs}ms` : stderr,
        durationMs: Date.now() - started,
        timedOut,
      });
    });

    child.on("error", (error) => {
      clearTimers();
      resolve({
        command,
        exitCode: -1,
        stdout,
        stderr: `${stderr}\n${String(error)}`,
        durationMs: Date.now() - started,
      });
    });
  });
}

async function runShell(
  command: string,
  cwd: string,
  options?: { streamOutput?: boolean; timeoutMs?: number },
): Promise<CommandResult> {
  return runShellWithOptions(command, cwd, {
    streamOutput: options?.streamOutput ?? false,
    timeoutMs: options?.timeoutMs,
  });
}

function dryRunCommand(command: string): CommandResult {
  return {
    command,
    exitCode: 0,
    stdout: "[dry-run] command not executed",
    stderr: "",
    durationMs: 0,
  };
}

function dryRunPi(options: PiInvocationOptions): CommandResult {
  const status: PiStatus = "success";

  const body =
    options.phaseName === "PLAN"
      ? {
          status,
          summary: "[dry-run] plan produced",
          reason: null,
          acceptanceCriteria: [],
          implementationPlan: [],
          filesLikelyToChange: [],
          risks: [],
        }
      : options.phaseName === "BUILD"
        ? {
            status,
            summary: "[dry-run] build produced",
            reason: null,
            filesChanged: [],
            issues: [],
          }
        : {
            status,
            summary: "[dry-run] verification produced",
            reason: null,
            issues: [],
            criteriaResults: [],
          };

  return {
    command: `pi [dry-run ${options.phaseName}]`,
    exitCode: 0,
    stdout: JSON.stringify(body, null, 2),
    stderr: "",
    durationMs: 0,
  };
}

function buildPlanPrompt(story: StoryContext): string {
  return [
    "PHASE: PLAN",
    "",
    "You are planning exactly one Kanban story using the plan-story skill.",
    `Story: ${story.storyPath}`,
    "",
    "Rules:",
    "- Do not edit ANY files other than story itself.",
    "- You must move the story from unplanned to planned.",
    "- You must not change any file other than the story file move/content.",
    "- Apply the skill plan-story skill as written, without deviation.",
    "- Return only strict JSON. No Markdown. No prose outside JSON.",
    "",
    "Deterministic verification feedback from previous attempt (if any):",
    ...(story.issues.length === 0
      ? ["- None"]
      : story.issues.map((issue) => `- ${issue}`)),
    "",
    "Return JSON with this shape:",
    "{",
    '  "status": "success" | "issue",',
    '  "summary": "string",',
    '  "reason": "string | null",',
    '  "acceptanceCriteria": ["string"],',
    '  "implementationPlan": ["string"],',
    '  "filesLikelyToChange": ["string"],',
    '  "risks": ["string"]',
    "}",
  ].join("\n");
}

function buildBuildPrompt(story: StoryContext): string {
  return [
    "PHASE: BUILD",
    "",
    `Story: ${story.storyPath}`,
    `Attempt: ${story.attempt}`,
    "",
    "You are building exactly one Kanban story.",
    "",
    "Rules:",
    "- Implement only the approved plan already present in this session and attached as plan.json.",
    "- Stay tightly scoped to the story.",
    "- Address the previous issues if any are supplied.",
    "- Do not move Kanban files.",
    "- Do not mark the story done.",
    "- Prefer minimal, idiomatic changes.",
    "- You may inspect, edit, write, and use bash only as needed for the implementation.",
    "- Return only strict JSON. No Markdown. No prose outside JSON.",
    "",
    "Previous issues:",
    ...story.issues.map((issue) => `- ${issue}`),
    "",
    "Return JSON with this shape:",
    "{",
    '  "status": "success" | "issue",',
    '  "summary": "string",',
    '  "reason": "string | null",',
    '  "filesChanged": ["string"],',
    '  "issues": ["string"]',
    "}",
  ].join("\n");
}

function buildVerifyPrompt(story: StoryContext): string {
  return [
    "PHASE: VERIFY",
    "",
    `Story: ${story.storyPath}`,
    `Attempt: ${story.attempt}`,
    "",
    "You are verifying exactly one Kanban story.",
    "",
    "Rules:",
    "- Do not edit files.",
    "- Do not fix issues.",
    "- Re-read the story and its acceptance criteria.",
    "- Compare the implementation to the acceptance criteria.",
    "- Consider the attached test and lint results.",
    "- If all acceptance criteria are met and tests/lint passed, return success.",
    "- If anything is incomplete, ambiguous, risky, or incorrect, return issue with concrete reasons.",
    "- Return only strict JSON. No Markdown. No prose outside JSON.",
    "",
    "Return JSON with this shape:",
    "{",
    '  "status": "success" | "issue",',
    '  "summary": "string",',
    '  "reason": "string | null",',
    '  "issues": ["string"],',
    '  "criteriaResults": [',
    "    {",
    '      "criterion": "string",',
    '      "met": true,',
    '      "evidence": "string",',
    '      "issue": "string | null"',
    "    }",
    "  ]",
    "}",
  ].join("\n");
}

function coercePlanResult(value: unknown): PlanResult {
  const obj = asObject(value);
  const status = coerceStatus(obj.status);

  return {
    status,
    summary: asOptionalString(obj.summary),
    reason: asOptionalNullableString(obj.reason),
    acceptanceCriteria: asStringArray(obj.acceptanceCriteria),
    implementationPlan: asStringArray(obj.implementationPlan),
    filesLikelyToChange: asStringArray(obj.filesLikelyToChange),
    risks: asStringArray(obj.risks),
  };
}

function coerceBuildResult(value: unknown): BuildResult {
  const obj = asObject(value);
  const status = coerceStatus(obj.status);

  return {
    status,
    summary: asOptionalString(obj.summary),
    reason: asOptionalNullableString(obj.reason),
    filesChanged: asStringArray(obj.filesChanged),
    issues: asStringArray(obj.issues),
  };
}

function coerceVerifyResult(value: unknown): VerifyResult {
  const obj = asObject(value);
  const status = coerceStatus(obj.status);

  return {
    status,
    summary: asOptionalString(obj.summary),
    reason: asOptionalNullableString(obj.reason),
    issues: asStringArray(obj.issues),
    criteriaResults: Array.isArray(obj.criteriaResults)
      ? obj.criteriaResults
          .filter((item) => typeof item === "object" && item !== null)
          .map((item) => {
            const criterion = asObject(item);
            return {
              criterion: String(criterion.criterion ?? ""),
              met: Boolean(criterion.met),
              evidence: asOptionalString(criterion.evidence),
              issue: asOptionalNullableString(criterion.issue),
            };
          })
      : [],
  };
}

function coerceStatus(value: unknown): PiStatus {
  return value === "success" ? "success" : "issue";
}

function asObject(value: unknown): Record<string, unknown> {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asOptionalString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function asOptionalNullableString(value: unknown): string | null | undefined {
  if (value === null) return null;
  return typeof value === "string" ? value : undefined;
}

function asStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function extractJsonObject(text: string): string | null {
  const trimmed = text.trim();

  // Whole output is a bare JSON object — fast path.
  if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
    return trimmed;
  }

  // Priority 1: Find the LAST raw JSON object in the output by walking
  // backwards from the last '}'. This correctly handles the common Pi pattern
  // of emitting prose or placeholder fenced blocks followed by a final bare
  // JSON answer at the end.
  const lastClose = trimmed.lastIndexOf("}");
  if (lastClose >= 0) {
    let depth = 0;
    for (let i = lastClose; i >= 0; i -= 1) {
      if (trimmed[i] === "}") depth += 1;
      else if (trimmed[i] === "{") {
        depth -= 1;
        if (depth === 0) {
          return trimmed.slice(i, lastClose + 1);
        }
      }
    }
  }

  // Priority 2: Collect every fenced code block and try them in REVERSE order.
  // Only reached when no bare JSON object was found in the output at all.
  const fencePattern = /```(?:json)?\s*(\{[\s\S]*?\})\s*```/gi;
  const fencedCandidates: string[] = [];
  let match: RegExpExecArray | null;

  while ((match = fencePattern.exec(trimmed)) !== null) {
    if (match[1]) {
      fencedCandidates.push(match[1].trim());
    }
  }

  for (let i = fencedCandidates.length - 1; i >= 0; i -= 1) {
    const candidate = fencedCandidates[i];
    if (candidate && candidate.startsWith("{") && candidate.endsWith("}")) {
      return candidate;
    }
  }

  return null;
}

async function ensureRuntimeDirectories(machine: Machine): Promise<void> {
  await mkdir(machine.runDir, { recursive: true });
  await mkdir(resolveFromRoot(machine.config, machine.config.sessionDir), { recursive: true });
  await mkdir(resolveFromRoot(machine.config, machine.config.doneDir), { recursive: true });
  await mkdir(resolveFromRoot(machine.config, machine.config.blockedDir), { recursive: true });

  await ensureExists(resolveFromRoot(machine.config, machine.config.storyDir), "story directory");
  await ensureExists(resolveFromRoot(machine.config, machine.config.planSkillPath), "plan skill");
  await ensureExists(resolveFromRoot(machine.config, machine.config.buildSkillPath), "build skill");
  await ensureExists(resolveFromRoot(machine.config, machine.config.verifySkillPath), "verify skill");

  await writeJson(path.join(machine.runDir, "run.json"), {
    runId: machine.runId,
    startedAt: new Date().toISOString(),
    config: machine.config,
  });
}

async function ensureExists(filePath: string, label: string): Promise<void> {
  try {
    await access(filePath);
  } catch {
    throw new Error(`Missing ${label}: ${filePath}`);
  }
}

async function writeStoryState(machine: Machine): Promise<void> {
  const story = requireStory(machine);

  await writeJson(nextStoryArtifactPath(story, "state.json"), {
    phase: machine.phase,
    originalStoryPath: story.originalStoryPath,
    storyPath: story.storyPath,
    storyId: story.storyId,
    sessionPath: story.sessionPath,
    attempt: story.attempt,
    planRepairAttempts: story.planRepairAttempts,
    artifactSequence: story.artifactSequence,
    artifacts: {
      planJsonPath: story.planJsonPath ?? null,
      buildJsonPath: story.buildJsonPath ?? null,
      testJsonPath: story.testJsonPath ?? null,
      lintJsonPath: story.lintJsonPath ?? null,
      verifyJsonPath: story.verifyJsonPath ?? null,
    },
    issues: story.issues,
    blockedReason: story.blockedReason ?? null,
    plan: story.plan ?? null,
    build: story.build ?? null,
    verify: story.verify ?? null,
    testResult: summarizeCommandResult(story.testResult),
    lintResult: summarizeCommandResult(story.lintResult),
  });
}

function summarizeCommandResult(result: CommandResult | undefined): unknown {
  if (!result) return null;

  return {
    command: result.command,
    exitCode: result.exitCode,
    durationMs: result.durationMs,
    stdoutBytes: Buffer.byteLength(result.stdout),
    stderrBytes: Buffer.byteLength(result.stderr),
  };
}

async function journal(machine: Machine, event: Record<string, unknown>): Promise<void> {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    ...event,
  });

  await writeFileAppend(path.join(machine.runDir, "events.ndjson"), `${line}\n`);
}

async function writeFileAppend(filePath: string, text: string): Promise<void> {
  const existing = await fileExists(filePath);
  if (!existing) {
    await writeFile(filePath, text, "utf8");
    return;
  }

  const previous = await readFile(filePath, "utf8");
  await writeFile(filePath, previous + text, "utf8");
}

async function writeJson(filePath: string, value: unknown): Promise<void> {
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

function renderIssues(issues: string[]): string {
  if (issues.length === 0) {
    return "# Previous issues\n\nNo previous issues.\n";
  }

  return [
    "# Previous issues",
    "",
    ...issues.map((issue) => `- ${issue}`),
    "",
  ].join("\n");
}

function renderFinalReport(
  machine: Machine,
  story: StoryContext,
  outcome: "done" | "blocked",
): string {
  return [
    `# Story ${outcome}`,
    "",
    `- Story: ${story.storyPath}`,
    `- Story ID: ${story.storyId}`,
    `- Attempts: ${story.attempt}`,
    `- Pi session: ${story.sessionPath}`,
    `- Run directory: ${story.storyRunDir}`,
    "",
    "## Planning",
    "",
    "```json",
    JSON.stringify(story.plan ?? null, null, 2),
    "```",
    "",
    "## Last build",
    "",
    "```json",
    JSON.stringify(story.build ?? null, null, 2),
    "```",
    "",
    "## Last verification",
    "",
    "```json",
    JSON.stringify(story.verify ?? null, null, 2),
    "```",
    "",
    "## Last test result",
    "",
    "```json",
    JSON.stringify(summarizeCommandResult(story.testResult), null, 2),
    "```",
    "",
    "## Last lint result",
    "",
    "```json",
    JSON.stringify(summarizeCommandResult(story.lintResult), null, 2),
    "```",
    "",
    "## Final issues",
    "",
    ...(story.issues.length === 0 ? ["None."] : story.issues.map((issue) => `- ${issue}`)),
    "",
    "## Blocked reason",
    "",
    story.blockedReason ?? "Not blocked.",
    "",
    "## Runner",
    "",
    `- Run ID: ${machine.runId}`,
    `- Dry run: ${machine.config.dryRun}`,
    "",
  ].join("\n");
}

function requireStory(machine: Machine): StoryContext {
  if (!machine.current) {
    throw new Error(`No current story in phase ${machine.phase}`);
  }
  return machine.current;
}

function resolveFromRoot(config: Config, value: string): string {
  return path.isAbsolute(value) ? value : path.resolve(config.rootDir, value);
}

function nextStoryArtifactPath(story: StoryContext, fileName: string): string {
  story.artifactSequence += 1;
  const sequence = String(story.artifactSequence).padStart(3, "0");
  return path.join(story.storyRunDir, `${sequence}-${fileName}`);
}

function resolveExpectedPlannedStoryPath(machine: Machine, story: StoryContext): string {
  const plannedDir = resolveFromRoot(machine.config, "./docs/kanban/planned");
  return path.resolve(plannedDir, path.basename(story.storyPath));
}

function toRepoRelativePosix(rootDir: string, absolutePath: string): string {
  return path.relative(rootDir, absolutePath).split(path.sep).join("/");
}

function parseGitStatusPaths(porcelain: string): string[] {
  const paths: string[] = [];

  for (const line of porcelain.split(/\r?\n/)) {
    if (!line.trim()) continue;
    const body = line.slice(3).trim();
    if (!body) continue;

    if (body.includes(" -> ")) {
      const [fromPath, toPath] = body.split(" -> ").map((part) => part.trim());
      if (fromPath) paths.push(fromPath);
      if (toPath) paths.push(toPath);
    } else {
      paths.push(body);
    }
  }

  return paths;
}

function safeName(value: string): string {
  return value
    .trim()
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 120);
}

function timestampForPath(date: Date): string {
  return date.toISOString().replace(/[:.]/g, "-");
}

function truncate(value: string, maxLength: number): string {
  if (value.length <= maxLength) return value;
  return `${value.slice(0, maxLength)}\n\n[truncated ${value.length - maxLength} chars]`;
}

function levelColor(level: LogLevel): string | undefined {
  if (level === "success") return ANSI.green;
  if (level === "error") return ANSI.red;
  return undefined;
}

function writeRunnerLine(
  message: string,
  level: LogLevel,
  stream: "stdout" | "stderr",
): void {
  const prefix = `${ANSI.grey}[runner]${ANSI.reset}`;
  const color = levelColor(level);
  const body = color ? `${color}${message}${ANSI.reset}` : message;
  const writer = stream === "stderr" ? process.stderr : process.stdout;
  writer.write(`${prefix} ${body}\n`);
}

function log(machine: Machine, message: string, level: LogLevel = "info"): void {
  if (machine.config.verbose) {
    const lines = message.split(/\r?\n/);
    for (const line of lines) {
      writeRunnerLine(line, level, "stdout");
    }
  }
}

function parseArgs(args: string[]): Config {
  const config: Config = { ...DEFAULT_CONFIG };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    const readValue = (): string => {
      const value = args[index + 1];
      if (!value) {
        throw new Error(`Missing value for ${arg}`);
      }
      index += 1;
      return value;
    };

    switch (arg) {
      case "--pi":
        config.piCommand = readValue();
        break;

      case "--root":
        config.rootDir = path.resolve(readValue());
        break;

      case "--story-dir":
        config.storyDir = readValue();
        break;

      case "--done-dir":
        config.doneDir = readValue();
        break;

      case "--blocked-dir":
        config.blockedDir = readValue();
        break;

      case "--run-dir-base":
        config.runDirBase = readValue();
        break;

      case "--session-dir":
        config.sessionDir = readValue();
        break;

      case "--plan-skill":
        config.planSkillPath = readValue();
        break;

      case "--build-skill":
        config.buildSkillPath = readValue();
        break;

      case "--verify-skill":
        config.verifySkillPath = readValue();
        break;

      case "--max-attempts":
        config.maxAttempts = Number.parseInt(readValue(), 10);
        if (!Number.isFinite(config.maxAttempts) || config.maxAttempts < 1) {
          throw new Error("--max-attempts must be a positive integer");
        }
        break;

      case "--pi-timeout": {
        const piSecs = Number.parseInt(readValue(), 10);
        if (!Number.isFinite(piSecs) || piSecs < 1) {
          throw new Error("--pi-timeout must be a positive integer (seconds)");
        }
        config.piTimeoutMs = piSecs * 1000;
        break;
      }

      case "--test-timeout": {
        const testSecs = Number.parseInt(readValue(), 10);
        if (!Number.isFinite(testSecs) || testSecs < 1) {
          throw new Error("--test-timeout must be a positive integer (seconds)");
        }
        config.testTimeoutMs = testSecs * 1000;
        break;
      }

      case "--limit":
        config.limit = Number.parseInt(readValue(), 10);
        if (!Number.isFinite(config.limit) || config.limit < 1) {
          throw new Error("--limit must be a positive integer");
        }
        break;

      case "--test":
        config.testCommand = readValue();
        break;

      case "--lint":
        config.lintCommand = readValue();
        break;

      case "--model":
        config.piModel = readValue();
        break;

      case "--provider":
        config.piProvider = readValue();
        break;

      case "--thinking":
        config.piThinking = readValue();
        break;

      case "--continue-on-blocked":
        config.continueOnBlocked = true;
        break;

      case "--dry-run":
        config.dryRun = true;
        break;

      case "--quiet":
        config.verbose = false;
        break;

      case "--help":
      case "-h":
        printHelpAndExit();

      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return config;
}

function printHelpAndExit(): never {
  console.log(`
implement-kanban-stories.ts

A deterministic state-machine runner around pi-mono.

Options:
  --pi <command>                 Pi command. Default: pi
  --root <dir>                   Repository root. Default: cwd
  --story-dir <dir>              Unplanned story directory. Default: ./docs/kanban/unplanned
  --done-dir <dir>               Done story directory. Default: ./docs/kanban/done
  --blocked-dir <dir>            Blocked story directory. Default: ./docs/kanban/blocked
  --run-dir-base <dir>           Run journal base directory. Default: .pi/runs
  --session-dir <dir>            Pi session directory. Default: .pi/story-sessions
  --plan-skill <path>            Plan skill path. Default: .github/skills/plan-story/SKILL.md
  --build-skill <path>           Build skill path. Default: .github/skills/build-story/SKILL.md
  --verify-skill <path>          Verify skill path. Default: .github/skills/verify-story/SKILL.md
  --limit <n>                    Limit number of stories processed (sorted order).
  --max-attempts <n>             Maximum build/fix attempts. Default: 8
  --pi-timeout <seconds>         Timeout for each Pi invocation. Default: 600 (10 min). Aborts the run on expiry.
  --test-timeout <seconds>       Timeout for each test/lint command. Default: 600 (10 min).
  --test <command>               Test command. Default: ./scripts/test-all.sh
  --lint <command>               Lint command. Default: ./scripts/lint-all.sh
  --provider <provider>          Optional Pi provider.
  --model <model>                Optional Pi model.
  --thinking <level>             Optional Pi thinking level.
  --continue-on-blocked          Continue to next story when a story blocks.
  --dry-run                      Do not call Pi, tests, lint, or move files.
  --quiet                        Reduce console output.
  --help                         Show this help.
`);
  process.exit(0);
}

main().catch((error) => {
  writeRunnerLine(
    error instanceof Error ? error.message : String(error),
    "error",
    "stderr",
  );
  process.exit(1);
});
