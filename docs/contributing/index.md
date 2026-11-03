# Contributing

Rayzr is developed in the open at
[github.com/bcrowe306/rayzr](https://github.com/bcrowe306/rayzr). Bug
reports, ideas, documentation fixes and code are all welcome.

## Report a bug

- In the editor: **Help > Report a Bug** opens a GitHub issue with your
  version and platform filled in. After a crash, the editor offers the
  crash report the next time it starts.
- Or open an issue on [GitHub](https://github.com/bcrowe306/rayzr/issues/new)
  with what you did, what you expected and what happened.

## Improve the docs

Every page of this site has an **Edit page** link at the bottom. The
documentation lives next to the code in the engine repository, so a fix is
a small pull request. See [Writing documentation](docs.md).

## Contribute code

1. Fork the repository and make a branch.
2. Build: `odin build editor -out:bin/editor` (the editor) and
   `task test` (the engine's unit tests). The
   [README](https://github.com/bcrowe306/rayzr#readme) lists the
   prerequisites.
3. Add a test with your change: an engine test (`engine/*_test.odin`) and,
   for editor features, a [test drive](../../editor/TEST_DRIVE.md).
4. Document it: a guide in `engine/docs/`, the property help in
   `engine/property_docs.odin`, and Lua functions in
   `engine/definitions/engine_api.lua` (each with an example).
5. Open a pull request. CI builds every platform and runs the tests; a
   change to the rendering, scene or viewport code also runs the
   [performance checks](performance.md) on a deliberately slow machine.

Every change merged into `main` becomes a development build within about
half an hour ([Releases and dev builds](../../RELEASING.md)).

## Contact

Email [support@rayzr.app](mailto:support@rayzr.app).
