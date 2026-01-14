# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive RuboCop configuration with sensible Ruby defaults
- MIT LICENSE file
- CHANGELOG.md for tracking version changes
- RSpec test infrastructure setup
- SimpleCov for test coverage tracking
- YARD documentation for all public APIs
- Error handling throughout the codebase
- Contributing guidelines and code of conduct

### Changed
- Updated gemspec with complete metadata
- Improved documentation in README

### Fixed
- All RuboCop linting violations

## [0.2.0] - 2025-01-XX

### Added
- Octokit integration for GitHub API operations
- PRComment model for structured comment handling
- `clean` command to remove state files
- `context` command to view accumulated learnings
- `progress` command to track session history
- `comments` command to fetch PR comments
- `pr` command to create pull requests

### Changed
- Enhanced GitHub integration with both Octokit gem and gh CLI fallback
- Improved PR body template with attribution links

### Fixed
- Various bug fixes and improvements

## [0.1.0] - 2025-01-XX

### Added
- Initial release
- Core autonomous loop implementation
- State management via `.claude-task-master/` directory
- Basic CLI commands: `start`, `resume`, `status`
- GitHub integration via gh CLI
- Claude CLI wrapper
- Planning and work execution phases

[Unreleased]: https://github.com/sebyx07/claude-task-master/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/sebyx07/claude-task-master/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sebyx07/claude-task-master/releases/tag/v0.1.0
