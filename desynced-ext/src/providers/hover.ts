import * as vscode from 'vscode';
import { InstructionMap } from '../instructionData';
import { parseBehDocument } from '../documentParser';
import { formatInstructionDoc } from './completion';

export class BehHoverProvider implements vscode.HoverProvider {
    constructor(private instructions: InstructionMap) {}

    provideHover(
        document: vscode.TextDocument,
        position: vscode.Position,
    ): vscode.Hover | undefined {
        const wordRange = document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/);
        if (!wordRange) { return undefined; }
        const word = document.getText(wordRange);

        // Check if it's a known instruction (used as function call)
        const lineText = document.lineAt(position.line).text;
        const afterWord = lineText.substring(wordRange.end.character).trimStart();

        if (this.instructions[word]) {
            const def = this.instructions[word];
            return new vscode.Hover(
                new vscode.MarkdownString(formatInstructionDoc(word, def)),
                wordRange
            );
        }

        // Check if it's a document symbol (param, var, function, label)
        const info = parseBehDocument(document);
        for (const sym of info.symbols) {
            if (sym.name === word) {
                let md = '';
                switch (sym.kind) {
                    case 'param':
                        md = `**Parameter** \`${sym.name}\``;
                        break;
                    case 'var':
                        md = `**Variable** \`${sym.name}\``;
                        break;
                    case 'function':
                        md = `**Function** \`${sym.name}(${(sym.params || []).join(', ')})\``;
                        if (sym.locals && sym.locals.length > 0) {
                            md += `\n\nLocals: ${sym.locals.map(l => `\`${l}\``).join(', ')}`;
                        }
                        break;
                    case 'label':
                        md = `**Label** \`${sym.name}\``;
                        break;
                    case 'functionArg':
                        md = `**Function argument** \`${sym.name}\``;
                        break;
                    case 'functionVar':
                        md = `**Function local** \`${sym.name}\``;
                        break;
                }
                if (md) {
                    return new vscode.Hover(new vscode.MarkdownString(md), wordRange);
                }
            }
        }

        return undefined;
    }
}
