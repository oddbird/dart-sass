// Copyright 2018 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as p;
import 'package:sass/src/util/nullable.dart';

import 'utils.dart';

@Task('Generate benchmark files.')
Future<void> benchmarkGenerate() async {
  var sources = Directory("build/benchmark");
  if (!await sources.exists()) await sources.create(recursive: true);

  await _writeNTimes("${sources.path}/small_plain.scss", ".foo {a: b}", 4);
  await _writeNTimes(
    "${sources.path}/large_plain.scss",
    ".foo {a: b}",
    math.pow(2, 17),
  );
  await _writeNTimes(
    "${sources.path}/preceding_sparse_extend.scss",
    ".foo {a: b}",
    math.pow(2, 17),
    header: '.x {@extend .y}',
    footer: '.y {a: b}',
  );
  await _writeNTimes(
    "${sources.path}/following_sparse_extend.scss",
    ".foo {a: b}",
    math.pow(2, 17),
    header: '.y {a: b}',
    footer: '.x {@extend .y}',
  );
  await _writeNTimes(
    "${sources.path}/preceding_dense_extend.scss",
    ".foo {a: b}",
    math.pow(2, 17),
    header: '.bar {@extend .foo}',
  );
  await _writeNTimes(
    "${sources.path}/following_dense_extend.scss",
    ".foo {a: b}",
    math.pow(2, 17),
    footer: '.bar {@extend .foo}',
  );

  cloneOrCheckout("https://github.com/twbs/bootstrap", "v4.1.3");
  await _writeNTimes(
    "${sources.path}/bootstrap.scss",
    "@import '../bootstrap/scss/bootstrap';",
    16,
  );

  cloneOrCheckout(
    "https://github.com/alex-page/sass-a11ycolor",
    "2e7ef93ec06f8bbec80b632863e4b2811618af89",
  );
  File("${sources.path}/a11ycolor.scss").writeAsStringSync("""
    @import '../sass-a11ycolor/dist';

    x {
      // Adapted from a11ycolor's test1.scss, which at one point was much slower
      // in JS than in the Dart VM.
      y: AU-a11ycolor(red, blue)
         AU-a11ycolor(#646464, #E0E0E0)
         AU-a11ycolor(green, blue)
         AU-a11ycolor(pink, blue)
         AU-a11ycolor(blue, blue)
         AU-a11ycolor(#c0c0c0, #c0c0c0)
         AU-a11ycolor(#231284, #ccc)
         AU-a11ycolor(#fff, #fff);
    }
  """);

  cloneOrCheckout("https://github.com/zaydek/duomo", "v0.7.12");
  File(
    "${sources.path}/duomo.scss",
  ).writeAsStringSync("@import '../duomo/scripts/duomo.scss'");

  var carbon = cloneOrCheckout(
    "https://github.com/carbon-design-system/ibm-cloud-cognitive",
    "@carbon/ibm-cloud-cognitive@1.0.0-rc.0",
  );
  await runAsync("yarn", arguments: ["install"], workingDirectory: carbon);
  File("${sources.path}/carbon.scss").writeAsStringSync(
    "@import '../ibm-cloud-cognitive/packages/"
    "cloud-cognitive/src/index-without-carbon-released-only'",
  );
}

/// Writes [times] instances of [text] to [path].
///
/// If [header] is passed, it's written before [text]. If [footer] is passed,
/// it's written after [text]. If the file already exists and is the expected
/// length, it's not written.
Future<void> _writeNTimes(
  String path,
  String text,
  num times, {
  String? header,
  String? footer,
}) async {
  var file = File(path);
  var expectedLength = (header == null ? 0 : header.length + 1) +
      (text.length + 1) * times +
      (footer == null ? 0 : footer.length + 1);
  if (file.existsSync() && file.lengthSync() == expectedLength) {
    log("$path already exists.");
    return;
  }

  log("Generating $path...");
  var sink = file.openWrite();
  header.andThen(sink.writeln);
  for (var i = 0; i < times; i++) {
    sink.writeln(text);
  }
  footer.andThen(sink.writeln);
  await sink.close();
}

@Task('Run benchmarks for Sass compilation speed.')
@Depends(
  benchmarkGenerate,
  "pkg-compile-snapshot",
  "pkg-compile-native",
  "pkg-npm-release",
)
Future<void> benchmark() async {
  var libsass = cloneOrCheckout('https://github.com/sass/libsass', 'master');
  var sassc = cloneOrCheckout('https://github.com/sass/sassc', 'master');

  await runAsync(
    "make",
    runOptions: RunOptions(
      workingDirectory: sassc,
      environment: {"SASS_LIBSASS_PATH": p.absolute(libsass)},
    ),
  );
  log("");

  var libsassRevision = await _revision(libsass);
  var sasscRevision = await _revision(sassc);
  var dartSassRevision = await _revision('.');
  var gPlusPlusVersion = await _version("g++");
  var nodeVersion = await _version("node");

  var perf = File("perf.md").readAsStringSync();
  perf = perf.replaceFirst(RegExp(r"This was tested against:\n\n[^]*?\n\n"), """
This was tested against:

* libsass $libsassRevision and sassc $sasscRevision compiled with $gPlusPlusVersion.
* Dart Sass $dartSassRevision on Dart ${Platform.version} and Node $nodeVersion.

""");

  var buffer = StringBuffer("""
# Measurements

I ran five instances of each configuration and recorded the fastest time.

""");

  var benchmarks = [
    ["small_plain.scss", "Small Plain CSS", "4 instances of `.foo {a: b}`"],
    ["large_plain.scss", "Large Plain CSS", "2^17 instances of `.foo {a: b}`"],
    [
      "preceding_sparse_extend.scss",
      "Preceding Sparse `@extend`",
      "`.x {@extend .y}`, 2^17 instances of `.foo {a: b}`, and then `.y {a: b}`",
    ],
    [
      "following_sparse_extend.scss",
      "Following Sparse `@extend`",
      "`.y {a: b}`, 2^17 instances of `.foo {a: b}`, and then `.x {@extend .y}`",
    ],
    [
      "preceding_dense_extend.scss",
      "Preceding Dense `@extend`",
      "`.bar {@extend .foo}` followed by 2^17 instances of `.foo {a: b}`",
    ],
    [
      "following_dense_extend.scss",
      "Following Dense `@extend`",
      "2^17 instances of `.foo {a: b}` followed by `.bar {@extend .foo}`",
    ],
    [
      "bootstrap.scss",
      "Bootstrap",
      "16 instances of importing the Bootstrap framework",
    ],
    [
      "a11ycolor.scss",
      "a11ycolor",
      "test cases for a computation-intensive color-processing library",
    ],
    [
      "duomo.scss",
      "Duomo",
      "the output of the numerically-intensive Duomo framework "
          "(skipping LibSass due to module system use)",
    ],
    [
      "carbon.scss",
      "Carbon",
      "the output of the import-intensive Carbon framework",
      "-I",
      "build/ibm-cloud-cognitive/node_modules",
    ],
  ];

  var libsassIncompatible = {"Duomo"};

  for (var info in benchmarks) {
    var path = p.join('build/benchmark', info[0]);
    var title = info[1];
    var description = info[2];
    var extraArgs = info.sublist(3);

    buffer.writeln("## $title");
    buffer.writeln();
    buffer.writeln("Running on a file containing $description:");
    buffer.writeln();

    Duration? sasscTime;
    if (!libsassIncompatible.contains(info[1])) {
      sasscTime = await _benchmark(p.join(sassc, 'bin', 'sassc'), [
        path,
        ...extraArgs,
      ]);
      buffer.writeln("* sassc: ${_formatTime(sasscTime)}");
    }

    var scriptSnapshotTime = await _benchmark(Platform.executable, [
      '--no-enable-asserts',
      p.join('build', 'sass.snapshot'),
      path,
      ...extraArgs,
    ]);
    buffer.writeln(
      "* Dart Sass from a script snapshot: "
      "${_formatTime(scriptSnapshotTime)}",
    );

    var nativeExecutableTime = await _benchmark(
      p.join('build', 'sass.native'),
      [path, ...extraArgs],
    );
    buffer.writeln(
      "* Dart Sass native executable: "
      "${_formatTime(nativeExecutableTime)}",
    );

    var nodeTime = await _benchmark("node", [
      p.join('build', 'npm', 'sass.js'),
      path,
      ...extraArgs,
    ]);
    buffer.writeln("* Dart Sass on Node.js: ${_formatTime(nodeTime)}");

    buffer.writeln();
    buffer.writeln(
      'Based on these numbers, Dart Sass from a native executable '
      'is approximately:',
    );
    buffer.writeln();
    if (sasscTime != null) {
      buffer.writeln('* ${_compare(nativeExecutableTime, sasscTime)} libsass');
    }
    buffer.writeln(
      '* ${_compare(nativeExecutableTime, nodeTime)} Dart Sass on Node',
    );
    buffer.writeln();
    log('');
  }

  buffer.write("# Prior Measurements");
  perf = perf.replaceFirst(
    RegExp(r"# Measurements\n[^]*# Prior Measurements"),
    buffer.toString(),
  );

  File("perf.md").writeAsStringSync(perf);
}

/// Returns the revision of the Git repository at [path].
Future<String> _revision(String path) async => (await runAsync(
      "git",
      arguments: ["rev-parse", "--short", "HEAD"],
      quiet: true,
      workingDirectory: path,
    ))
        .trim();

/// Returns the first line of output from `executable --version`.
Future<String> _version(String executable) async => (await runAsync(
      executable,
      arguments: ["--version"],
      quiet: true,
    ))
        .split("\n")
        .first;

Future<Duration> _benchmark(String executable, List<String> arguments) async {
  log("$executable ${arguments.join(' ')}");

  // Run the benchmark once without recording output to give implementations a
  // chance to warm up at the OS level.
  await _benchmarkOnce(executable, arguments);

  Duration? lowest;
  for (var i = 0; i < 5; i++) {
    var duration = await _benchmarkOnce(executable, arguments);
    if (lowest == null || duration < lowest) lowest = duration;
  }
  return lowest!;
}

Future<Duration> _benchmarkOnce(
  String executable,
  List<String> arguments,
) async {
  var result = await Process.run("sh", [
    "-c",
    "time $executable ${arguments.join(' ')}",
  ]);

  if (result.exitCode != 0) {
    fail("Process failed with exit code ${result.exitCode}\n${result.stderr}");
  }

  var match = RegExp(
    r"(\d+)m(\d+)\.(\d+)s",
  ).firstMatch(result.stderr as String);
  if (match == null) {
    fail("Process didn't print the expected format:\n${result.stderr}");
  }

  return Duration(
    minutes: int.parse(match[1]!),
    seconds: int.parse(match[2]!),
    milliseconds: int.parse(match[3]!),
  );
}

String _formatTime(Duration duration) =>
    "${duration.inSeconds}." +
    (duration.inMilliseconds % 1000).toString().padLeft(3, '0') +
    's';

/// Returns an approximate, human-readable comparison between [duration1] and
/// [duration2].
String _compare(Duration duration1, Duration duration2) {
  var faster = duration1 < duration2;
  var ratio = faster
      ? duration2.inMilliseconds / duration1.inMilliseconds
      : duration1.inMilliseconds / duration2.inMilliseconds;
  var rounded = (ratio * 10).round().toString();
  var humanRatio = '${rounded.substring(0, rounded.length - 1)}.'
      '${rounded.substring(rounded.length - 1)}x';
  if (humanRatio == '1.0x') return 'identical to';

  return humanRatio + (faster ? ' faster than' : ' slower than');
}
