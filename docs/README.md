# Dana Wallet - Developer Documentation

> Comprehensive coding standards and development guidelines for Dana wallet contributors and AI assistants.

## 📚 Documentation Overview

This directory contains complete documentation for developing Dana wallet, a Bitcoin silent payments wallet built with Flutter and Rust.

### Quick Start

- **New to Dana?** Start with [ARCHITECTURE.md](./ARCHITECTURE.md)
- **Writing code?** Check [CODING_STANDARDS.md](./CODING_STANDARDS.md)
- **Making commits?** Follow [GIT_WORKFLOW.md](./GIT_WORKFLOW.md)
- **Building the app?** See [DEVELOPMENT.md](./DEVELOPMENT.md)

---

## 📖 Documentation Files

### 1. [ARCHITECTURE.md](./ARCHITECTURE.md)
**Project Structure & Design Patterns**

Understand Dana's architecture:
- Technology stack (Flutter + Rust)
- Directory organization (109 Dart files, ~30 Rust files)
- Layered architecture (data/business/presentation)
- Module organization and boundaries
- State management with Provider
- Rust FFI integration
- Data flow patterns

**Read this if you:**
- Are new to the codebase
- Need to understand where to place new files
- Want to know how components interact
- Need to understand the state management approach

### 2. [CODING_STANDARDS.md](./CODING_STANDARDS.md)
**Code Style & Conventions**

Learn Dana's coding practices:
- **Dart/Flutter Standards:**
  - File naming (snake_case with suffixes)
  - Class/function naming (PascalCase/camelCase)
  - Import organization (3-section structure)
  - Design patterns (Singleton, Factory, Enum extensions)
  - Commenting guidelines (strategic, not extensive)
  
- **Rust Standards:**
  - Module structure and file organization
  - Error handling (anyhow::Result)
  - Type conventions (Api prefix, newtype pattern)
  - Common idioms (lazy_static, StreamSink)

**Read this if you:**
- Are writing new code
- Reviewing pull requests
- Want to match Dana's style
- Need to understand naming conventions

### 3. [GIT_WORKFLOW.md](./GIT_WORKFLOW.md)
**Commit Conventions & Git Practices**

Master Dana's git workflow:
- Commit message format (Conventional Commits style)
- Commit types (`feat:`, `fix:`, `refactor:`, etc.)
- Scope notation (`feat(dev):`, `build(android):`)
- Real examples from Dana's 699+ commits
- Branch naming conventions
- Pull request guidelines
- Best practices

**Read this if you:**
- Are making commits
- Writing commit messages
- Creating pull requests
- Want to maintain clean git history

### 4. [DEVELOPMENT.md](./DEVELOPMENT.md)
**Setup, Build & Development Workflow**

Get up and running:
- Prerequisites (Flutter, Rust, tools)
- Initial setup instructions
- Build system (justfile commands)
- Running the app (different flavors/platforms)
- Development workflow (hot reload, debugging)
- Code generation (flutter_rust_bridge)
- Testing strategy
- Troubleshooting common issues

**Read this if you:**
- Are setting up your development environment
- Need to build the app
- Want to run on different platforms (Android/iOS/Desktop)
- Encountering build issues
- Need to regenerate FFI bindings

---

## 🎯 Use Cases

### For New Developers

**Day 1: Getting Started**
1. Read [ARCHITECTURE.md](./ARCHITECTURE.md) - Understand the big picture
2. Follow [DEVELOPMENT.md](./DEVELOPMENT.md) - Set up and run the app
3. Skim [CODING_STANDARDS.md](./CODING_STANDARDS.md) - Get familiar with conventions

**Day 2-7: First Contributions**
1. Study [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) - Learn commit conventions
2. Reference [CODING_STANDARDS.md](./CODING_STANDARDS.md) - While writing code
3. Use [ARCHITECTURE.md](./ARCHITECTURE.md) - To understand where your changes fit

### For LLM/AI Assistants

When helping with Dana wallet development:

**For General Questions:**
- Start with [ARCHITECTURE.md](./ARCHITECTURE.md) for context

**For Code Generation:**
1. Check [ARCHITECTURE.md](./ARCHITECTURE.md) - Understand where code belongs
2. Follow [CODING_STANDARDS.md](./CODING_STANDARDS.md) - Match Dana's style
3. Reference existing patterns in the codebase

**For Commits:**
- Follow [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) exactly

**For Build Issues:**
- Consult [DEVELOPMENT.md](./DEVELOPMENT.md) troubleshooting section

### For Code Reviewers

**Reviewing Pull Requests:**
1. Verify commit messages follow [GIT_WORKFLOW.md](./GIT_WORKFLOW.md)
2. Check code matches [CODING_STANDARDS.md](./CODING_STANDARDS.md)
3. Ensure changes align with [ARCHITECTURE.md](./ARCHITECTURE.md) patterns
4. Confirm build instructions in [DEVELOPMENT.md](./DEVELOPMENT.md) still work

---

## 🔑 Key Principles

Dana wallet development follows these core principles:

### 1. Self-Documenting Code
- Code should be clear through naming and structure
- Comments are strategic, not extensive
- Function and variable names explain intent

### 2. Consistency
- Follow established patterns
- Use existing code as examples
- Match the style of surrounding code

### 3. Separation of Concerns
- Clear boundaries between layers
- Data ↔ Business Logic ↔ Presentation
- Dart ↔ Rust FFI boundary

### 4. Type Safety
- Leverage Dart's null safety
- Use Rust's strong type system
- Explicit conversions at FFI boundary

### 5. Commit Clarity
- Conventional Commits format
- Clear, descriptive messages
- One logical change per commit

---

## 📊 Project Statistics

**Codebase Size:**
- 109 Dart files
- ~30 Rust source files
- 699+ git commits

**Technology:**
- Flutter 3.5.2+
- Rust (latest stable)
- flutter_rust_bridge 2.11.1

**Version:** 0.7.1-rc2 (experimental)

**Architecture:**
- 3-tier layered (Data/Business/Presentation)
- Feature-based module organization
- Provider pattern for state management
- Singleton pattern for repositories

---

## 🚀 Quick Reference

### File Naming

```
✅ wallet_repository.dart
✅ wallet_state.dart
✅ wallet_settings_screen.dart
✅ footer_button.dart
```

### Commit Messages

```
✅ feat: Add contact search functionality
✅ fix: Initialize contact list on restore
✅ refactor: Rename 'spAddress' to 'paymentCode'
✅ chore: Update flutter secure storage to 10.0.0
```

### Common Commands

```bash
# Run app
just run

# Build for Android
just build-android

# Generate Rust bindings
just gen

# Format code
fvm flutter format .

# Analyze code
fvm flutter analyze
```

---

## 🤝 Contributing

Before submitting code:

- [ ] Read relevant documentation
- [ ] Follow coding standards
- [ ] Use proper commit message format
- [ ] Test your changes
- [ ] Update documentation if needed

---

## 📞 Support

**Questions or Issues?**
- Check documentation first
- Search existing GitHub issues
- File a new issue with details

**Improving Documentation:**
- Found an error? Open an issue
- Have suggestions? Open a PR
- Documentation is never perfect - help us improve it!

---

## 📝 Document Maintenance

**When to Update Documentation:**

Update [ARCHITECTURE.md](./ARCHITECTURE.md) when:
- Project structure changes
- New architectural patterns introduced
- Major refactoring of layers/modules

Update [CODING_STANDARDS.md](./CODING_STANDARDS.md) when:
- New coding conventions adopted
- Patterns change or evolve
- Adding new best practices

Update [GIT_WORKFLOW.md](./GIT_WORKFLOW.md) when:
- Commit format changes
- New commit types added
- Branching strategy changes

Update [DEVELOPMENT.md](./DEVELOPMENT.md) when:
- Build process changes
- Dependencies updated
- New tools added

---

## 🎓 Learning Path

**Week 1: Understand**
- Read all documentation
- Explore codebase
- Run the app locally
- Make small fixes

**Week 2-4: Contribute**
- Pick up good first issues
- Write code following standards
- Get code reviews
- Learn from feedback

**Month 2+: Expert**
- Help review PRs
- Mentor new contributors
- Propose improvements
- Update documentation

---

**Last Updated:** February 2026  
**Dana Version:** 0.7.1-rc2  
**Maintainers:** Dana Wallet Team

---

**Happy Coding! 🚀**

*Building the future of Bitcoin privacy, one commit at a time.*
