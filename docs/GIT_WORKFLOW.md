# Dana Wallet Git Workflow

> Git commit conventions, branching strategy, and contribution guidelines for the Dana wallet project.

## Table of Contents

- [Overview](#overview)
- [Commit Message Format](#commit-message-format)
- [Commit Types](#commit-types)
- [Commit Examples](#commit-examples)
- [Best Practices](#best-practices)
- [Branch Naming](#branch-naming)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Quick Reference](#quick-reference)

---

## Overview

Dana wallet follows **Conventional Commits** style for clear, semantic commit messages. This provides:

- **Clear history** that's easy to understand
- **Automatic changelog generation** potential
- **Semantic versioning** support
- **LLM-friendly** commit parsing

**Statistics from Dana codebase:**
- 699+ commits analyzed
- Primary commit types: `feat`, `refactor`, `fix`, `chore`, `build`
- Consistent format across 90%+ of commits

---

## Commit Message Format

### Basic Structure

```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

### Components

#### 1. Type (Required)

Describes the category of change. See [Commit Types](#commit-types) section.

#### 2. Scope (Optional)

Specifies what part of the codebase is affected:

```
feat(dev): Add skip button on dana register screen
build(android): Rename Dev flavor app Development -> Experimental
refactor(screens): Reorganize wallet screen components
```

**Common scopes in Dana:**
- `(dev)` - Development-specific features
- `(android)` - Android platform changes
- `(ios)` - iOS platform changes  
- `(screens)` - UI screen changes
- `(wallet)` - Wallet logic
- `(sync)` - Blockchain synchronization
- `(state)` - State management
- `(onboarding)` - Onboarding flow

#### 3. Description (Required)

Short summary of the change:

- ✅ Use imperative mood ("Add feature" not "Added feature")
- ✅ Start with capital letter
- ✅ No period at the end
- ✅ Keep under 72 characters
- ✅ Be specific and descriptive

```
✅ feat: Add skip button on dana register screen
✅ fix: Initialize contact list on restoring from file
✅ refactor: Rename 'spAddress' to 'paymentCode'

❌ feat: new feature
❌ fix: fixed bug
❌ update: changed some stuff
```

#### 4. Body (Optional)

Detailed explanation of the change:

- Explain **WHY** the change was made (not just WHAT)
- Wrap at 72 characters
- Separate from description with blank line
- Can be multiple paragraphs

```
feat(dev): Add skip button on dana register screen

Add a skip button to the register dana address screen for the 'dev'
flavor. This allows developers to quickly test the app without
registering a Dana address during development.
```

#### 5. Footer (Optional)

Used for:
- Breaking changes: `BREAKING CHANGE: <description>`
- Issue references: `Fixes #123`, `Closes #456`
- Co-authors: `Co-authored-by: Name <email>`

---

## Commit Types

### Primary Types (Most Common)

#### `feat:` - New Features

A new feature or functionality for users.

**Examples from Dana:**
```
feat: Add 'local' flavor
feat: Set default network type for local flavor
feat: Treat local flavor same as Dev flavor
feat(dev): Add skip button on dana register screen
feat(wallet): Add support for custom fees
feat(onboarding): Implement new onboarding redesign
```

**When to use:**
- Adding new user-facing features
- Adding new API endpoints
- Adding new screens or UI components
- Implementing new workflows

#### `fix:` - Bug Fixes

A fix for a bug or issue.

**Examples from Dana:**
```
fix: Initialize contact list on restoring from file
fix: Log resolved payment code instead of input field
fix(sync): Don't update blindbit url when receiving an error
fix(state): Correctly handle wallet state after wipe
fix(spend): Validate payment code when adding contact
```

**When to use:**
- Fixing crashes
- Fixing incorrect behavior
- Fixing UI bugs
- Patching security issues

**Note:** Dana also uses `bug fix:` and `Bug fix:` (less common variants)

#### `refactor:` - Code Refactoring

Code changes that neither fix bugs nor add features.

**Examples from Dana:**
```
refactor: Rename 'spAddress' to 'paymentCode'
refactor: Drop old unused variables in spwallet
refactor: Move 'you' contact to separate variable
refactor(screens): Reorganize wallet screen components
refactor(wallet): Use structs instead of encoded Strings
```

**When to use:**
- Renaming variables/functions
- Restructuring code
- Removing dead code
- Improving code quality
- Performance optimizations (non-breaking)

#### `chore:` - Maintenance Tasks

Changes to build process, tooling, dependencies, or project maintenance.

**Examples from Dana:**
```
chore: Update flutter secure storage to 10.0.0
chore: Rename main_dev.dart -> main_local.dart
chore: Run local flavor in justfile
chore: Set local flavor as default when building
chore: Create new release candidate 0.7.1-rc1
```

**When to use:**
- Updating dependencies
- Modifying build scripts
- Configuration changes
- Release preparation
- Documentation updates (non-user-facing)

#### `build:` - Build System Changes

Changes to build configuration, CI/CD, or release process.

**Examples from Dana:**
```
build: Create release candidate 0.7.1-rc2
build(android): Rename Dev flavor app Development -> Experimental
build(justfile): Drop build-apk recipes
```

**When to use:**
- Gradle/build.gradle changes
- justfile modifications
- CI/CD pipeline updates
- Release versioning

### Secondary Types (Less Common)

#### `style:` - Code Style

Code style/formatting changes (no logic changes).

**Examples from Dana:**
```
style: Dart format
style: Cargo fmt
```

**When to use:**
- Running formatters
- Fixing linting warnings
- Whitespace/indentation changes

#### `docs:` - Documentation

Documentation-only changes.

**Examples from Dana:**
```
Update README
Expand README.md and add Building section
Add README for rust folder
```

**Note:** Dana often doesn't prefix README updates with `docs:`, but this is recommended.

#### `test:` - Tests

Adding or updating tests.

**When to use:**
- Adding new tests
- Fixing broken tests
- Improving test coverage

**Note:** Dana is in experimental phase with no formal tests yet.

#### `perf:` - Performance

Performance improvements.

**When to use:**
- Optimizing algorithms
- Reducing memory usage
- Improving rendering performance

---

## Commit Examples

### Example 1: Feature with Scope and Body

```
feat(dev): Add skip button on dana register screen

Add a skip button to the register dana address screen for the 'dev'
flavor. This allows developers to quickly test the app without
registering a Dana address during development.
```

**Analysis:**
- ✅ Type: `feat` (new feature)
- ✅ Scope: `(dev)` (development-only feature)
- ✅ Clear description: What was added
- ✅ Body: Explains why (developer convenience)

### Example 2: Refactor with Detailed Reasoning

```
refactor: Rename 'spAddress' to 'paymentCode'

Rename silent payment address to payment code. The term 'address' is
overloaded because of Dana addresses, and 'spAddress' was never a good
term to begin with. 'Payment code' might not be the most flashy name,
but I think it more clearly describes the point: to function as a code
that the user can be paid with.

Note: in the UI, we never use either the term 'silent payment' or
'payment code'. Instead we use 'static address'.
```

**Analysis:**
- ✅ Type: `refactor` (renaming, no new functionality)
- ✅ Clear description: What was renamed
- ✅ Body: Extensive reasoning for the change
- ✅ Additional context: UI terminology clarification

### Example 3: Build/Release

```
build: Create release candidate 0.7.1-rc2
```

**Analysis:**
- ✅ Type: `build` (release management)
- ✅ Simple description: Version bump
- ✅ No body needed: Change is self-explanatory

### Example 4: Fix without Scope

```
Bug fix: initialize contact list on restoring from file
```

**Analysis:**
- ⚠️ Type: `Bug fix` (should be `fix:` for consistency)
- ✅ Clear description: What bug was fixed

**Improved version:**
```
fix: Initialize contact list on restoring from file
```

### Example 5: Chore (Dependency Update)

```
chore: Update flutter secure storage to 10.0.0
```

**Analysis:**
- ✅ Type: `chore` (dependency update)
- ✅ Clear description: What was updated and to which version

### Example 6: Multiple Related Changes

**❌ Bad (too vague):**
```
Update settings
```

**✅ Good (specific):**
```
refactor: Settings reorganized by categories
```

or even better with body:

```
refactor(screens): Reorganize settings by categories

Group related settings into categories (Wallet, Network, Display)
to improve discoverability and reduce clutter.
```

---

## Best Practices

### 1. One Logical Change Per Commit

Each commit should represent **one logical change**.

```
✅ Good: Separate commits
  - feat: Add contact search functionality
  - refactor: Rename 'spAddress' to 'paymentCode'
  - fix: Validate payment code when adding contact

❌ Bad: One commit with multiple unrelated changes
  - feat: Add contact search, rename variables, and fix validation
```

### 2. Commit Often, Push Carefully

- Make small, frequent commits locally
- Squash/rebase before pushing if needed
- Each pushed commit should be meaningful

### 3. Write in Imperative Mood

Use imperative mood (command form) in descriptions:

```
✅ Add contact search functionality
✅ Fix validation bug
✅ Refactor wallet state management

❌ Added contact search functionality
❌ Fixed validation bug
❌ Refactoring wallet state management
```

**Tip:** A good commit message should complete: "If applied, this commit will..."
- "If applied, this commit will **Add contact search functionality**" ✅
- "If applied, this commit will **Added contact search**" ❌

### 4. Explain WHY, Not WHAT

The code shows WHAT changed. The commit message should explain WHY.

```
✅ Good:
refactor: Move getCurrentFeeRates to chainState

Fee rate fetching is chain-related, not wallet-related. Moving it to
chainState improves separation of concerns and makes the code more
maintainable.

❌ Bad:
refactor: Move function to different file

Moved the getCurrentFeeRates function from wallet.dart to chain_state.dart
```

### 5. Use Present Tense

```
✅ Add feature
✅ Fix bug
✅ Update dependency

❌ Added feature
❌ Fixed bug
❌ Updated dependency
```

### 6. Reference Issues When Relevant

```
fix: Retry fetching block height on timeout

Blindbit occasionally times out during block height fetching, causing
sync to fail. Now retries up to 3 times with exponential backoff.

Fixes #236
```

### 7. Breaking Changes

Use `BREAKING CHANGE:` footer for breaking changes:

```
feat: Remove deprecated wallet blob API

The wallet blob API has been deprecated since v0.5.0 and is now removed.
All code should use the new wallet repository pattern.

BREAKING CHANGE: WalletBlob class removed. Use WalletRepository instead.
```

### 8. Keep Description Concise

Description should be clear but brief (under 72 characters):

```
✅ feat: Add BIP353 address resolution
✅ fix: Prevent race condition in sync service
✅ refactor: Extract fee calculation to separate service

❌ feat: Add BIP353 address resolution to allow users to use human-readable addresses instead of silent payment addresses
```

**Tip:** Use the body for details, keep the description short.

---

## Branch Naming

While Dana's specific branch naming strategy isn't extensively documented in the commit history, here are recommended conventions:

### Feature Branches

```
feature/<description>
feat/<description>

Examples:
feature/contact-search
feat/custom-fees
feature/bip353-support
```

### Bug Fix Branches

```
fix/<issue-number>-<description>
fix/<description>

Examples:
fix/236-block-height-timeout
fix/contact-validation
```

### Refactoring Branches

```
refactor/<description>

Examples:
refactor/rename-sp-address
refactor/wallet-state-cleanup
```

### Release Branches

```
release/<version>

Examples:
release/0.7.1
release/0.8.0-rc1
```

### Hotfix Branches

```
hotfix/<version>-<description>

Examples:
hotfix/0.7.1-critical-security
```

---

## Pull Request Guidelines

### PR Title

Use the same format as commit messages:

```
feat: Add contact search functionality
fix: Initialize contact list on restore
refactor: Reorganize settings by categories
```

### PR Description

Include:

1. **Summary:** What does this PR do?
2. **Motivation:** Why is this change needed?
3. **Testing:** How was it tested?
4. **Screenshots:** (for UI changes)
5. **Breaking Changes:** (if any)
6. **Related Issues:** Links to issues

**Example:**

```markdown
## Summary
Adds contact search functionality to quickly find contacts by name or Dana address.

## Motivation
As the contact list grows, users need a way to quickly find specific contacts
without scrolling. This implements a search bar at the top of the contacts screen.

## Testing
- Tested on Android emulator and iOS simulator
- Verified search works with both contact names and Dana addresses
- Tested edge cases (empty list, no matches, special characters)

## Screenshots
[Include screenshots here]

## Related Issues
Closes #145
```

### PR Size

Keep PRs reasonably sized:
- ✅ Small, focused PRs (< 500 lines)
- ⚠️ Medium PRs (500-1000 lines) - consider splitting
- ❌ Large PRs (> 1000 lines) - should be split

### Code Review

Before requesting review:
- [ ] All tests pass (when tests exist)
- [ ] Code follows Dana coding standards
- [ ] Commit messages follow conventions
- [ ] No debug code or console logs left behind
- [ ] Documentation updated if needed

---

## Quick Reference

### Commit Type Decision Tree

```
Is it a new feature or capability?
  → feat:

Is it fixing a bug or issue?
  → fix:

Is it changing code structure without changing behavior?
  → refactor:

Is it updating dependencies or build configuration?
  → chore: or build:

Is it only formatting/style changes?
  → style:

Is it documentation only?
  → docs:

Is it performance optimization?
  → perf:

Is it adding/updating tests?
  → test:
```

### Commit Message Template

```
<type>[optional scope]: <description>

[optional body]

[optional footer]
```

### Common Patterns in Dana

```
feat: Add new functionality
feat(dev): Add developer-specific feature
fix: Fix user-facing bug
bug fix: Fix user-facing bug (alternative)
refactor: Improve code structure
refactor(screens): Improve screen organization
chore: Update dependencies or configuration
build: Release or build system changes
build(android): Android-specific build changes
style: Format code (Dart format, Cargo fmt)
```

### Commit Message Checklist

- [ ] Type is correct and lowercase (except for legacy `Bug fix`)
- [ ] Description starts with capital letter
- [ ] Description uses imperative mood ("Add" not "Added")
- [ ] Description is under 72 characters
- [ ] Description is specific and clear
- [ ] Body explains WHY (if needed)
- [ ] Body wraps at 72 characters (if used)
- [ ] Breaking changes noted in footer (if any)
- [ ] Issues referenced in footer (if applicable)

---

## Related Documentation

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Project structure and architecture  
- [CODING_STANDARDS.md](./CODING_STANDARDS.md) - Code style and conventions
- [DEVELOPMENT.md](./DEVELOPMENT.md) - Development setup and build process

---

## Resources

- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [How to Write a Git Commit Message](https://chris.beams.io/posts/git-commit/)
- [Angular Commit Message Guidelines](https://github.com/angular/angular/blob/main/CONTRIBUTING.md#commit)

---

**Last Updated:** February 2026  
**Dana Version:** 0.7.1-rc2  
**Maintainers:** Dana Wallet Team
