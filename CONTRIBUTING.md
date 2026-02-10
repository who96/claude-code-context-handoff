# Contributing to Claude Code Context Handoff

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful, constructive, and professional. We're all here to make Claude Code better.

## How to Contribute

### Reporting Bugs

Before creating a bug report:
1. Check existing issues to avoid duplicates
2. Test with the latest version
3. Verify the issue isn't caused by other hooks/plugins

Include in your bug report:
- Claude Code version (`claude --version`)
- Operating system
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs (use `claude --debug`)
- Contents of handoff file (if applicable)

### Suggesting Enhancements

Enhancement suggestions are welcome. Please:
1. Check if it's already been suggested
2. Explain the use case clearly
3. Describe the expected behavior
4. Consider backward compatibility

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature-name`
3. **Make your changes**:
   - Follow existing code style
   - Add comments for complex logic
   - Update documentation if needed
4. **Test thoroughly**:
   - Run `./test.sh`
   - Test installation/uninstallation
   - Test with real Claude Code sessions
5. **Commit with clear messages**:
   ```
   feat: add configurable retention policy
   fix: handle empty transcript files
   docs: update troubleshooting guide
   ```
6. **Push and create PR**

## Development Setup

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-context-handoff.git
cd claude-code-context-handoff

# Test installation locally
./install.sh

# Make changes to hooks/
# Test changes
./test.sh

# Uninstall
./uninstall.sh
```

## Code Style

### Python (pre-compact-handoff.py)
- Follow PEP 8
- Use type hints where helpful
- Keep functions focused and small
- Add docstrings for non-obvious functions

### Bash (session-restore.sh, install.sh, uninstall.sh)
- Use `set -euo pipefail`
- Quote all variables: `"$var"`
- Use `[[` instead of `[` for conditionals
- Add comments for non-obvious logic

## Testing

Before submitting:
1. Test installation on clean system
2. Test with real Claude Code sessions
3. Test uninstallation
4. Verify no leftover files
5. Check settings.json is valid JSON

## Documentation

Update documentation when:
- Adding new features
- Changing behavior
- Adding configuration options
- Fixing bugs that affect usage

Files to update:
- `README.md` - User-facing documentation
- `CHANGELOG.md` - Version history
- Code comments - Implementation details

## Release Process

(For maintainers)

1. Update version in `plugin.json`
2. Update `CHANGELOG.md`
3. Create git tag: `git tag v1.x.x`
4. Push tag: `git push origin v1.x.x`
5. Create GitHub release with changelog

## Questions?

Open an issue with the `question` label.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
