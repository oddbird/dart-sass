// Copyright 2017 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

@TestOn('vm')
library;

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'package:sass/sass.dart';
import 'package:sass/src/exception.dart';

import 'dart_api/test_importer.dart';

void main() {
  // TODO(nweiz): test SASS_PATH when dart-lang/sdk#28160 is fixed.

  group("importers", () {
    test("is used to resolve imports", () async {
      await d.dir("subdir", [d.file("subtest.scss", "a {b: c}")]).create();
      await d.file("test.scss", '@use "subtest.scss";').create();

      var css = compile(
        d.path("test.scss"),
        importers: [FilesystemImporter(d.path('subdir'))],
      );
      expect(css, equals("a {\n  b: c;\n}"));
    });

    test("are checked in order", () async {
      await d.dir("first", [
        d.file("other.scss", "a {b: from-first}"),
      ]).create();
      await d.dir("second", [
        d.file("other.scss", "a {b: from-second}"),
      ]).create();
      await d.file("test.scss", '@use "other";').create();

      var css = compile(
        d.path("test.scss"),
        importers: [
          FilesystemImporter(d.path('first')),
          FilesystemImporter(d.path('second')),
        ],
      );
      expect(css, equals("a {\n  b: from-first;\n}"));
    });
  });

  group("loadPaths", () {
    test("is used to import file: URLs", () async {
      await d.dir("subdir", [d.file("subtest.scss", "a {b: c}")]).create();
      await d.file("test.scss", '@use "subtest.scss";').create();

      var css = compile(d.path("test.scss"), loadPaths: [d.path('subdir')]);
      expect(css, equals("a {\n  b: c;\n}"));
    });

    test("can import partials", () async {
      await d.dir("subdir", [d.file("_subtest.scss", "a {b: c}")]).create();
      await d.file("test.scss", '@use "subtest.scss";').create();

      var css = compile(d.path("test.scss"), loadPaths: [d.path('subdir')]);
      expect(css, equals("a {\n  b: c;\n}"));
    });

    test("adds a .scss extension", () async {
      await d.dir("subdir", [d.file("subtest.scss", "a {b: c}")]).create();
      await d.file("test.scss", '@use "subtest";').create();

      var css = compile(d.path("test.scss"), loadPaths: [d.path('subdir')]);
      expect(css, equals("a {\n  b: c;\n}"));
    });

    test("adds a .sass extension", () async {
      await d.dir("subdir", [d.file("subtest.sass", "a\n  b: c")]).create();
      await d.file("test.scss", '@use "subtest";').create();

      var css = compile(d.path("test.scss"), loadPaths: [d.path('subdir')]);
      expect(css, equals("a {\n  b: c;\n}"));
    });

    test("are checked in order", () async {
      await d.dir("first", [
        d.file("other.scss", "a {b: from-first}"),
      ]).create();
      await d.dir("second", [
        d.file("other.scss", "a {b: from-second}"),
      ]).create();
      await d.file("test.scss", '@use "other";').create();

      var css = compile(
        d.path("test.scss"),
        loadPaths: [d.path('first'), d.path('second')],
      );
      expect(css, equals("a {\n  b: from-first;\n}"));
    });
  });

  group("packageResolver", () {
    test("is used to import package: URLs", () async {
      await d.dir("subdir", [d.file("test.scss", "a {b: 1 + 2}")]).create();

      await d.file("test.scss", '@use "package:fake_package/test";').create();
      var config = PackageConfig([
        Package('fake_package', p.toUri(d.path('subdir/'))),
      ]);

      var css = compile(d.path("test.scss"), packageConfig: config);
      expect(css, equals("a {\n  b: 3;\n}"));
    });

    test("can resolve relative paths in a package", () async {
      await d.dir("subdir", [
        d.file("test.scss", "@use 'other'"),
        d.file("_other.scss", "a {b: 1 + 2}"),
      ]).create();

      await d.file("test.scss", '@use "package:fake_package/test";').create();
      var config = PackageConfig([
        Package('fake_package', p.toUri(d.path('subdir/'))),
      ]);

      var css = compile(d.path("test.scss"), packageConfig: config);
      expect(css, equals("a {\n  b: 3;\n}"));
    });

    test("doesn't import a package URL from a missing package", () async {
      await d
          .file("test.scss", '@use "package:fake_package/test_aux";')
          .create();

      expect(
        () => compile(d.path("test.scss"), packageConfig: PackageConfig([])),
        throwsA(const TypeMatcher<SassRuntimeException>()),
      );
    });
  });

  group("import precedence", () {
    test("relative imports take precedence over importers", () async {
      await d.dir("subdir", [
        d.file("other.scss", "a {b: from-load-path}"),
      ]).create();
      await d.file("other.scss", "a {b: from-relative}").create();
      await d.file("test.scss", '@use "other";').create();

      var css = compile(
        d.path("test.scss"),
        importers: [FilesystemImporter(d.path('subdir'))],
      );
      expect(css, equals("a {\n  b: from-relative;\n}"));
    });

    test(
        "the original importer takes precedence over other importers for "
        "relative imports", () async {
      await d.dir("original", [
        d.file("other.scss", "a {b: from-original}"),
      ]).create();
      await d.dir("other", [
        d.file("other.scss", "a {b: from-other}"),
      ]).create();

      var css = compileString(
        '@use "other";',
        importer: FilesystemImporter(d.path('original')),
        url: p.toUri(d.path('original/test.scss')),
        importers: [FilesystemImporter(d.path('other'))],
      );
      expect(css, equals("a {\n  b: from-original;\n}"));
    });

    test("importer order is preserved for absolute imports", () {
      var css = compileString(
        '@use "second:other";',
        importers: [
          TestImporter(
            (url) => url.scheme == 'first' ? url : null,
            (url) => ImporterResult('a {from: first}', indented: false),
          ),
          // This importer should only be invoked once, because when the
          // "first:other" import is resolved it should be passed to the first
          // importer first despite being in the second importer's file.
          TestImporter(
            expectAsync1(
              (url) => url.scheme == 'second' ? url : null,
              count: 1,
            ),
            (url) => ImporterResult('@use "first:other";', indented: false),
          ),
        ],
      );
      expect(css, equals("a {\n  from: first;\n}"));
    });

    test("importers take precedence over load paths", () async {
      await d.dir("load-path", [
        d.file("other.scss", "a {b: from-load-path}"),
      ]).create();
      await d.dir("importer", [
        d.file("other.scss", "a {b: from-importer}"),
      ]).create();
      await d.file("test.scss", '@use "other";').create();

      var css = compile(
        d.path("test.scss"),
        importers: [FilesystemImporter(d.path('importer'))],
        loadPaths: [d.path('load-path')],
      );
      expect(css, equals("a {\n  b: from-importer;\n}"));
    });

    test("importers take precedence over packageConfig", () async {
      await d.dir("package", [
        d.file("other.scss", "a {b: from-package-config}"),
      ]).create();
      await d.dir("importer", [
        d.file("other.scss", "a {b: from-importer}"),
      ]).create();
      await d.file("test.scss", '@use "package:fake_package/other";').create();

      var css = compile(
        d.path("test.scss"),
        importers: [
          PackageImporter(
            PackageConfig([
              Package('fake_package', p.toUri(d.path('importer/'))),
            ]),
          ),
        ],
        packageConfig: PackageConfig([
          Package('fake_package', p.toUri(d.path('package/'))),
        ]),
      );
      expect(css, equals("a {\n  b: from-importer;\n}"));
    });
  });

  group("charset", () {
    group("= true", () {
      test("doesn't emit @charset for a pure-ASCII stylesheet", () {
        expect(
          compileString("a {b: c}"),
          equalsIgnoringWhitespace("""
            a {
              b: c;
            }
          """),
        );
      });

      test("emits @charset with expanded output", () async {
        expect(
          compileString("a {b: 👭}"),
          equalsIgnoringWhitespace("""
            @charset "UTF-8";
            a {
              b: 👭;
            }
          """),
        );
      });

      test("emits a BOM with compressed output", () async {
        expect(
          compileString("a {b: 👭}", style: OutputStyle.compressed),
          equals("\u{FEFF}a{b:👭}"),
        );
      });
    });

    group("= false", () {
      test("doesn't emit @charset with expanded output", () async {
        expect(
          compileString("a {b: 👭}", charset: false),
          equalsIgnoringWhitespace("""
            a {
              b: 👭;
            }
          """),
        );
      });

      test("emits a BOM with compressed output", () async {
        expect(
          compileString(
            "a {b: 👭}",
            charset: false,
            style: OutputStyle.compressed,
          ),
          equals("a{b:👭}"),
        );
      });
    });
  });

  group("loadedUrls", () {
    group("contains the entrypoint's URL", () {
      group("in compileStringToResult()", () {
        test("if it's given", () {
          var result = compileStringToResult("a {b: c}", url: "source.scss");
          expect(result.loadedUrls, equals([Uri.parse("source.scss")]));
        });

        test("unless it's not given", () {
          var result = compileStringToResult("a {b: c}");
          expect(result.loadedUrls, isEmpty);
        });
      });

      test("in compileToResult()", () async {
        await d.file("input.scss", "a {b: c};").create();
        var result = compileToResult(d.path('input.scss'));
        expect(result.loadedUrls, equals([p.toUri(d.path('input.scss'))]));
      });
    });

    test("contains a URL loaded via @import", () async {
      await d.file("_other.scss", "a {b: c}").create();
      await d.file("input.scss", "@import 'other';").create();
      var result = compileToResult(
        d.path('input.scss'),
        silenceDeprecations: [Deprecation.import],
      );
      expect(result.loadedUrls, contains(p.toUri(d.path('_other.scss'))));
    });

    test("contains a URL loaded via @use", () async {
      await d.file("_other.scss", "a {b: c}").create();
      await d.file("input.scss", "@use 'other';").create();
      var result = compileToResult(d.path('input.scss'));
      expect(result.loadedUrls, contains(p.toUri(d.path('_other.scss'))));
    });

    test("contains a URL loaded via @forward", () async {
      await d.file("_other.scss", "a {b: c}").create();
      await d.file("input.scss", "@forward 'other';").create();
      var result = compileToResult(d.path('input.scss'));
      expect(result.loadedUrls, contains(p.toUri(d.path('_other.scss'))));
    });

    test("contains a URL loaded via @meta.load-css()", () async {
      await d.file("_other.scss", "a {b: c}").create();
      await d.file("input.scss", """
        @use 'sass:meta';
        @include meta.load-css('other');
      """).create();
      var result = compileToResult(d.path('input.scss'));
      expect(result.loadedUrls, contains(p.toUri(d.path('_other.scss'))));
    });

    test("contains a URL loaded via a chain of loads", () async {
      await d.file("_jupiter.scss", "a {b: c}").create();
      await d.file("_mars.scss", "@forward 'jupiter';").create();
      await d.file("_earth.scss", "@import 'mars';").create();
      await d.file("_venus.scss", "@use 'earth';").create();
      await d.file("mercury.scss", """
        @use 'sass:meta';
        @include meta.load-css('venus');
      """).create();
      var result = compileToResult(
        d.path('mercury.scss'),
        silenceDeprecations: [Deprecation.import],
      );
      expect(
        result.loadedUrls,
        unorderedEquals([
          p.toUri(d.path('mercury.scss')),
          p.toUri(d.path('_venus.scss')),
          p.toUri(d.path('_earth.scss')),
          p.toUri(d.path('_mars.scss')),
          p.toUri(d.path('_jupiter.scss')),
        ]),
      );
    });
  });

  // Regression test for #1318
  test("meta.load-module() doesn't have a race condition", () async {
    await d.file("other.scss", '/**//**/').create();
    expect(
      compileStringAsync(
        """
          @use 'sass:meta';
          @include meta.load-css("other.scss");
        """,
        loadPaths: [d.sandbox],
      ),
      completion(equals("/**/ /**/")),
    );

    // Give the race condition time to appear.
    await pumpEventQueue();
  });
}
