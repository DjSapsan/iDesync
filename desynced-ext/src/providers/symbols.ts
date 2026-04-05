import * as vscode from 'vscode';
import { parseBehDocument } from '../documentParser';

export class BehDocumentSymbolProvider implements vscode.DocumentSymbolProvider {
    provideDocumentSymbols(document: vscode.TextDocument): vscode.DocumentSymbol[] {
        const info = parseBehDocument(document);
        const symbols: vscode.DocumentSymbol[] = [];

        for (const sym of info.symbols) {
            let kind: vscode.SymbolKind;
            let detail = '';
            switch (sym.kind) {
                case 'param':
                    kind = vscode.SymbolKind.Field;
                    detail = 'parameter';
                    break;
                case 'var':
                    kind = vscode.SymbolKind.Variable;
                    detail = 'variable';
                    break;
                case 'function':
                    kind = vscode.SymbolKind.Function;
                    detail = `(${(sym.params || []).join(', ')})`;
                    break;
                case 'label':
                    kind = vscode.SymbolKind.Key;
                    detail = 'label';
                    break;
                default:
                    continue; // skip functionArg/functionVar from top-level outline
            }

            const docSym = new vscode.DocumentSymbol(
                sym.name,
                detail,
                kind,
                sym.range,
                sym.nameRange,
            );
            symbols.push(docSym);
        }

        return symbols;
    }
}
