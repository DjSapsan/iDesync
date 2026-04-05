import * as vscode from 'vscode';
import { InstructionMap } from '../instructionData';
import { parseBehDocument } from '../documentParser';

export function createDiagnostics(
    document: vscode.TextDocument,
    instructions: InstructionMap,
    collection: vscode.DiagnosticCollection,
) {
    if (document.languageId !== 'beh') {
        return;
    }

    const diagnostics: vscode.Diagnostic[] = [];
    const info = parseBehDocument(document);

    // Collect all known names in scope
    const knownNames = new Set<string>();
    for (const sym of info.symbols) {
        knownNames.add(sym.name);
    }

    // Built-in keywords that look like function calls
    const builtinCalls = new Set([
        'goto', 'label', 'wait', 'compare', 'foreach',
    ]);

    for (const call of info.calls) {
        const name = call.name;

        // Skip known user-defined functions, labels used as goto targets, builtins
        if (builtinCalls.has(name)) { continue; }

        // Check if it's a known instruction or user-defined function
        const isInstruction = name in instructions;
        const isUserFunc = info.symbols.some(s => s.kind === 'function' && s.name === name);

        if (!isInstruction && !isUserFunc) {
            diagnostics.push(new vscode.Diagnostic(
                call.range,
                `Unknown instruction or function: '${name}'`,
                vscode.DiagnosticSeverity.Warning,
            ));
        }

        // Validate argument count for known instructions
        if (isInstruction) {
            const def = instructions[name];
            if (def.args && call.argsRange) {
                const argsText = document.getText(call.argsRange).trim();
                if (argsText.length > 0) {
                    // Count comma-separated args (rough estimate)
                    const argCount = argsText.split(',').length;
                    const requiredArgs = def.args.filter(a => a.direction === 'in' && !a.extra).length;
                    const maxArgs = def.args.filter(a => a.direction === 'in').length;
                    if (argCount > maxArgs) {
                        diagnostics.push(new vscode.Diagnostic(
                            call.range,
                            `'${name}' expects at most ${maxArgs} input argument(s), got ${argCount}`,
                            vscode.DiagnosticSeverity.Warning,
                        ));
                    }
                }
            }
        }
    }

    // Check goto targets exist as labels
    for (const call of info.calls) {
        if (call.name === 'goto' && call.argsRange) {
            // This is handled by the goto call pattern - skip
        }
    }

    // Check for goto referencing non-existent labels
    const text = document.getText();
    const gotoRe = /\bgoto\s*\(\s*([a-zA-Z_]\w*)\s*\)/g;
    let gm: RegExpExecArray | null;
    const labelNames = new Set(info.symbols.filter(s => s.kind === 'label').map(s => s.name));
    while ((gm = gotoRe.exec(text)) !== null) {
        const labelName = gm[1];
        if (!labelNames.has(labelName)) {
            const start = document.positionAt(gm.index);
            const end = document.positionAt(gm.index + gm[0].length);
            diagnostics.push(new vscode.Diagnostic(
                new vscode.Range(start, end),
                `Label '${labelName}' is not defined`,
                vscode.DiagnosticSeverity.Error,
            ));
        }
    }

    collection.set(document.uri, diagnostics);
}
