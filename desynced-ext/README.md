# Desync Behavior Language Support

A Visual Studio Code extension that provides language support for the Desync game's behavior programming language. This extension enhances the development experience when writing behavior scripts for autonomous units in Desync.

## Features

- Full syntax highlighting for .beh files
- Code snippets for common behavior patterns
- Support for behavior-specific language constructs:
  - Params and vars declarations
  - Flow control (if, repeat, foreach, compare blocks)
  - Built-in functions
  - Comments with -- syntax

### Syntax Highlighting

The extension provides syntax highlighting for:
- Keywords and control structures
- Built-in functions and commands
- Variables and parameters
- Comments
- String literals
- Numeric values

### Code Snippets

Quick shortcuts for common behavior patterns:

- `params` - Parameters declaration block
- `vars` - Variables declaration block
- `if` - If statement block
- `repeat` - Repeat loop structure
- `compare_block` - Compare block with equal/larger/smaller sections
- `foreach` - Foreach loop structure
- `function` - Function declaration with local vars
- Various game-specific commands like:
  - Resource management
  - Unit control
  - Navigation
  - Combat
  - Base building

## Requirements

- Visual Studio Code 1.98.0 or newer
- Desync game (for actual script usage)

## Installation

1. Clone this repository
2. Copy it to your VSCode extensions folder:
   - Windows: %USERPROFILE%\.vscode\extensions
   - macOS/Linux: ~/.vscode/extensions
3. Restart Visual Studio Code

## Language Configuration

The extension configures:
- Comment toggling (-- for line comments)
- Bracket matching for ()
- Auto-closing pairs
- Surrounding pairs support

## Development

This extension is in active development. Planned features:
- Enhanced IntelliSense support
- In-editor documentation
- Diagnostic reporting
- Hover information
- Go to definition support

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

[Add your chosen license here]

---

## Building From Source

1. Clone the repository
2. Run `npm install`
3. Make your changes
4. Press F5 to launch the extension development sandbox

## Acknowledgements

- Thanks to the Desync game developers for the behavior language specification
- Built using the VS Code Extension API

**Enjoy writing behaviors for Desync!**
