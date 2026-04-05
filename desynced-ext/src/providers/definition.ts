import * as vscode from 'vscode';
import { parseBehDocument } from '../documentParser';

export class BehDefinitionProvider implements vscode.DefinitionProvider {
    provideDefinition(
        document: vscode.TextDocument,
        position: vscode.Position,
    ): vscode.Location | undefined {
        const wordRange = document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/);
        if (!wordRange) { return undefined; }
        const word = document.getText(wordRange);

        const info = parseBehDocument(document);

        // Check if we're inside a goto(...) call — jump to label definition
        const lineText = document.lineAt(position.line).text;
        const gotoMatch = lineText.match(/\bgoto\s*\(\s*([a-zA-Z_]\w*)\s*\)/);
        if (gotoMatch && gotoMatch[1] === word) {
            const labelSym = info.symbols.find(s => s.kind === 'label' && s.name === word);
            if (labelSym) {
                return new vscode.Location(document.uri, labelSym.nameRange);
            }
        }

        // Check if clicking on a function call — jump to function definition
        for (const call of info.calls) {
            if (call.range.contains(position)) {
                const funcSym = info.symbols.find(s => s.kind === 'function' && s.name === word);
                if (funcSym) {
                    return new vscode.Location(document.uri, funcSym.nameRange);
                }
            }
        }

        // Check if clicking on a variable — jump to its declaration
        const declSym = info.symbols.find(s =>
            (s.kind === 'param' || s.kind === 'var') && s.name === word
        );
        if (declSym) {
            return new vscode.Location(document.uri, declSym.nameRange);
        }

        return undefined;
    }
}
