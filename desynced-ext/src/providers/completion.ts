import * as vscode from 'vscode';
import { InstructionMap, InstructionArg } from '../instructionData';
import { parseBehDocument } from '../documentParser';

export class BehCompletionProvider implements vscode.CompletionItemProvider {
    constructor(private instructions: InstructionMap) {}

    provideCompletionItems(
        document: vscode.TextDocument,
        position: vscode.Position,
    ): vscode.CompletionItem[] {
        const items: vscode.CompletionItem[] = [];

        // Instruction completions
        for (const [id, def] of Object.entries(this.instructions)) {
            const item = new vscode.CompletionItem(id, vscode.CompletionItemKind.Function);
            item.detail = `${def.name} [${def.category || ''}]`;
            item.documentation = new vscode.MarkdownString(formatInstructionDoc(id, def));

            // Build snippet with arg placeholders
            const inArgs = (def.args || []).filter(a => a.direction === 'in' && !a.extra);
            const outArgs = (def.args || []).filter(a => a.direction === 'out');
            if (outArgs.length > 0 && inArgs.length > 0) {
                const outs = outArgs.map((a, i) => `\${${i + 1}:${a.name}}`).join(', ');
                const ins = inArgs.map((a, i) => `\${${outArgs.length + i + 1}:${a.name}}`).join(', ');
                item.insertText = new vscode.SnippetString(`${outs} = ${id}(${ins})`);
            } else if (inArgs.length > 0) {
                const ins = inArgs.map((a, i) => `\${${i + 1}:${a.name}}`).join(', ');
                item.insertText = new vscode.SnippetString(`${id}(${ins})`);
            } else if (outArgs.length > 0) {
                const outs = outArgs.map((a, i) => `\${${i + 1}:${a.name}}`).join(', ');
                item.insertText = new vscode.SnippetString(`${outs} = ${id}()`);
            } else {
                item.insertText = new vscode.SnippetString(`${id}()`);
            }

            items.push(item);
        }

        // Variable/param/function completions from current document
        const info = parseBehDocument(document);
        for (const sym of info.symbols) {
            if (sym.kind === 'param') {
                const item = new vscode.CompletionItem(sym.name, vscode.CompletionItemKind.Field);
                item.detail = 'parameter';
                items.push(item);
            } else if (sym.kind === 'var') {
                const item = new vscode.CompletionItem(sym.name, vscode.CompletionItemKind.Variable);
                item.detail = 'variable';
                items.push(item);
            } else if (sym.kind === 'function') {
                const item = new vscode.CompletionItem(sym.name, vscode.CompletionItemKind.Function);
                item.detail = `function(${(sym.params || []).join(', ')})`;
                items.push(item);
            } else if (sym.kind === 'label') {
                const item = new vscode.CompletionItem(sym.name, vscode.CompletionItemKind.Constant);
                item.detail = 'label';
                items.push(item);
            }
        }

        return items;
    }
}

function formatInstructionDoc(id: string, def: { name: string; desc?: string; category?: string; args?: InstructionArg[] }): string {
    let md = `**${def.name}** \`${id}\`\n\n`;
    if (def.desc) { md += `${def.desc}\n\n`; }
    if (def.args && def.args.length > 0) {
        md += '**Arguments:**\n';
        for (const arg of def.args) {
            const dir = arg.direction === 'in' ? '\u2192' : arg.direction === 'out' ? '\u2190' : '\u21AA';
            const filter = arg.filter ? ` \`${arg.filter}\`` : '';
            const extra = arg.extra ? ' *(optional)*' : '';
            const desc = arg.desc ? ` \u2014 ${arg.desc}` : '';
            md += `- ${dir} **${arg.name}**${filter}${desc}${extra}\n`;
        }
    }
    return md;
}

export { formatInstructionDoc };
