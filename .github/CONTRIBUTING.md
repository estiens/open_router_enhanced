# Contributing to OpenRouter Enhanced

Thank you for your interest in contributing to OpenRouter Enhanced! This document provides guidelines and instructions for contributing.

## Branch Strategy

We use a simple two-branch strategy:

- **`main`** - Stable releases only. Protected branch.
- **`dev`** - Active development. All PRs should target this branch.

### Workflow

1. Fork the repository
2. Create a feature branch from `dev`
3. Make your changes
4. Submit a PR targeting the `dev` branch

**Important:** Always target `dev` branch with your PRs, not `main`.

## Development Setup

```bash
# Clone your fork
git clone https://github.com/your-username/open_router.git
cd open_router

# Checkout dev branch
git checkout dev

# Install dependencies
bundle install

# Run tests
bundle exec rake spec

# Run linter
bundle exec rubocop
```

## Making Changes

### Code Style

- Follow existing code style and conventions
- Run RuboCop before committing: `bundle exec rubocop`
- Auto-fix issues when possible: `bundle exec rubocop -a`
- Keep methods small and focused (Sandi Metz rules)

### Testing

All changes must include tests:

```bash
# Run unit tests (fast)
bundle exec rake spec

# Run VCR integration tests (requires API key)
export OPENROUTER_API_KEY="your_key"
bundle exec rake spec_vcr

# Run all tests
bundle exec rake spec_all
```

### Test Coverage

- Write tests for all new features
- Update existing tests for bug fixes
- Include both unit tests and VCR integration tests
- Ensure all tests pass before submitting PR

### Documentation

Update documentation for any changes:

- Code comments for complex logic
- README.md for user-facing features
- docs/* for detailed feature documentation
- Examples in examples/* for new capabilities
- MIGRATION.md for breaking changes

## Pull Request Process

### Before Submitting

- [ ] All tests passing
- [ ] RuboCop clean (0 offenses)
- [ ] Documentation updated
- [ ] Examples added/updated if needed
- [ ] Backward compatibility maintained (unless explicitly breaking)

### PR Title Format

Use conventional commit format:

```
feat: Add new feature description
fix: Fix bug description
docs: Update documentation
test: Add or update tests
refactor: Code refactoring
perf: Performance improvement
chore: Maintenance tasks
```

### PR Description

Use the provided PR template and fill out all relevant sections.

## Types of Contributions

### Bug Fixes

1. Create an issue describing the bug (if not exists)
2. Write a failing test that reproduces the bug
3. Fix the bug
4. Ensure test passes
5. Submit PR referencing the issue

### New Features

1. Create an issue to discuss the feature first
2. Get feedback from maintainers
3. Implement with tests
4. Update documentation
5. Add examples
6. Submit PR

### Documentation

Documentation improvements are always welcome:
- Fix typos
- Clarify confusing sections
- Add examples
- Update outdated information

### Examples

High-quality examples help users:
- Real-world use cases
- Best practices demonstrations
- Integration patterns
- Working code that users can run

## Code Review Process

1. PR submitted to `dev` branch
2. Automated checks run (tests, linting)
3. Maintainer reviews code
4. Feedback addressed by contributor
5. PR approved and merged to `dev`
6. Changes included in next release

## Release Process

Releases are managed by maintainers:

1. Changes accumulate in `dev` branch
2. Version bumped according to SemVer
3. CHANGELOG updated
4. `dev` merged to `main`
5. Tag created and pushed
6. Gem published to RubyGems

## Backward Compatibility

We take backward compatibility seriously:

- **Major version (x.0.0)**: Breaking changes allowed
- **Minor version (1.x.0)**: New features, no breaking changes
- **Patch version (1.0.x)**: Bug fixes only

For v1.x releases:
- Maintain full backward compatibility
- Deprecate before removing features
- Provide migration guides for any breaking changes in v2.0

## Getting Help

- **Questions**: Open a GitHub Discussion
- **Bugs**: Open a GitHub Issue
- **Security**: See SECURITY.md
- **Features**: Open an issue to discuss first

## Code of Conduct

- Be respectful and inclusive
- Welcome newcomers
- Provide constructive feedback
- Focus on the code, not the person
- Assume good intentions

## Recognition

Contributors will be:
- Listed in release notes
- Mentioned in CHANGELOG
- Credited in documentation (where appropriate)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to OpenRouter Enhanced! 🚀
