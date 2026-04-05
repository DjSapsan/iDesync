import * as vscode from 'vscode';
import { InstructionMap } from '../instructionData';

export class BehSignatureHelpProvider implements vscode.SignatureHelpProvider {
    constructor(private instructions: InstructionMap) {}

    provideSignatureHelp(
        document: vscode.TextDocument,
        position: vscode.Position,
    ): vscode.SignatureHelp | undefined {
        // Walk backwards from cursor to find the function name and current arg index
        const lineText = document.lineAt(position.line).text;
        const textBefore = lineText.substring(0, position.character);

        // Find the innermost open paren
        let depth = 0;
        let parenPos = -1;
        let commaCount = 0;
        for (let i = textBefore.length - 1; i >= 0; i--) {
            const ch = textBefore[i];
            if (ch === ')') { depth++; }
            else if (ch === '(') {
                if (depth === 0) { parenPos = i; break; }
                depth--;
            } else if (ch === ',' && depth === 0) {
                commaCount++;
            }
        }

        if (parenPos < 0) { return undefined; }

        // Extract function name before the paren
        const beforeParen = textBefore.substring(0, parenPos).trimEnd();
        const nameMatch = beforeParen.match(/([a-zA-Z_]\w*)$/);
        if (!nameMatch) { return undefined; }
        const funcName = nameMatch[1];

        const def = this.instructions[funcName];
        if (!def || !def.args) { return undefined; }

        const inArgs = def.args.filter(a => a.direction === 'in');
        if (inArgs.length === 0) { return undefined; }

        const sigLabel = `${funcName}(${inArgs.map(a => a.name).join(', ')})`;
        const sig = new vscode.SignatureInformation(sigLabel);
        sig.documentation = new vscode.MarkdownString(def.desc || '');

        for (const arg of inArgs) {
            const paramDoc = arg.desc ? `${arg.desc}${arg.filter ? ` (${arg.filter})` : ''}` : (arg.filter || '');
            sig.parameters.push(new vscode.ParameterInformation(arg.name, paramDoc));
        }

        const help = new vscode.SignatureHelp();
        help.signatures = [sig];
        help.activeSignature = 0;
        help.activeParameter = Math.min(commaCount, inArgs.length - 1);

        return help;
    }
}
