# Release Process

Follow these steps in order to publish a new version of GraphLink.

---

## 1. Update the help message in `lib/src/main.dart`

If any new config options were added, update the help text printed by `glink --help`:

- Add new options under the relevant `clientConfig.*` or `serverConfig.*` section
- Follow the existing column alignment: name (left), type, description, default in brackets
- Test it: `dart run lib/src/main.dart --help`

---

## 2. Update the version in `pubspec.yaml`

Edit the `version` field:

```yaml
version: <new-version>
```

Example: `4.3.1` → `4.4.0`

---

## 3. Update `CHANGELOG.md`

Get the commits since the last tag, excluding the `examples/` directory:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline -- . ':(exclude)examples'
```

Use that output to write a new section at the bottom of `CHANGELOG.md`:

```markdown
## <new-version> - <YYYY-MM-DD>
  - Description of changes
```

---

## 4. Commit the changes

```bash
git add pubspec.yaml CHANGELOG.md lib/src/main.dart
git commit -m "chore: bump version to <new-version>"
```

---

## 5. Create and push a git tag

```bash
git tag v<new-version>
git push origin main
git push origin v<new-version>
```

Example:

```bash
git tag v4.4.0
git push origin main
git push origin v4.4.0
```

---

## 6. Publish to pub.dev

```bash
dart pub publish
```

> Confirm the prompt when asked. Make sure you are authenticated (`dart pub login`).

---

## Notes

- Use [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`
  - `PATCH` — bug fixes
  - `MINOR` — new backwards-compatible features
  - `MAJOR` — breaking changes
- The tag must match the version in `pubspec.yaml` prefixed with `v`.
