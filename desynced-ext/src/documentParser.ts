import * as vscode from 'vscode';

export interface BehSymbol {
    name: string;
    kind: 'param' | 'var' | 'function' | 'label' | 'functionArg' | 'functionVar';
    range: vscode.Range;
    nameRange: vscode.Range;
    /** For functions: parameter names */
    params?: string[];
    /** For functions: local var names */
    locals?: string[];
}

export interface BehDocumentInfo {
    symbols: BehSymbol[];
    /** All function call sites: name + range */
    calls: { name: string; range: vscode.Range; argsRange?: vscode.Range }[];
}

/**
 * Parse a .beh document and extract symbols and call sites.
 * This is a lightweight regex-based parser for IDE features.
 */
export function parseBehDocument(document: vscode.TextDocument): BehDocumentInfo {
    const text = document.getText();
    const symbols: BehSymbol[] = [];
    const calls: BehDocumentInfo['calls'] = [];

    // params [...] block
    const paramsRe = /\bparams\s*\[([\s\S]*?)\]/g;
    let m: RegExpExecArray | null;
    while ((m = paramsRe.exec(text)) !== null) {
        const blockStart = m.index + m[0].indexOf('[') + 1;
        parseVarList(document, m[1], blockStart, 'param', symbols);
    }

    // vars [...] or var [...] block
    const varsRe = /\bvars?\s*\[([\s\S]*?)\]/g;
    while ((m = varsRe.exec(text)) !== null) {
        const blockStart = m.index + m[0].indexOf('[') + 1;
        parseVarList(document, m[1], blockStart, 'var', symbols);
    }

    // function definitions: function name (args)\n  vars (locals)
    const funcRe = /\b(function)\s+([a-zA-Z_]\w*)\s*\(([^)]*)\)/g;
    while ((m = funcRe.exec(text)) !== null) {
        const nameStart = m.index + m[0].indexOf(m[2]);
        const namePos = document.positionAt(nameStart);
        const nameEnd = document.positionAt(nameStart + m[2].length);

        // Find matching 'end' for the function
        const funcBodyStart = m.index + m[0].length;
        const endIdx = findMatchingEnd(text, funcBodyStart);
        const funcEnd = endIdx >= 0 ? document.positionAt(endIdx + 3) : nameEnd;

        const params = m[3].split(/[,\s]+/).map(s => s.trim()).filter(Boolean);

        // Look for vars (...) inside function body
        const bodyText = text.substring(funcBodyStart, endIdx >= 0 ? endIdx : text.length);
        const funcVarsRe = /\bvars?\s*\(([^)]*)\)/;
        const vm = funcVarsRe.exec(bodyText);
        const locals = vm ? vm[1].split(/[\s,]+/).map(s => s.trim()).filter(Boolean) : [];

        symbols.push({
            name: m[2],
            kind: 'function',
            range: new vscode.Range(document.positionAt(m.index), funcEnd),
            nameRange: new vscode.Range(namePos, nameEnd),
            params,
            locals,
        });

        // Also add function args and locals as symbols
        for (const p of params) {
            const argIdx = text.indexOf(p, nameStart);
            if (argIdx >= 0) {
                const pos = document.positionAt(argIdx);
                const end = document.positionAt(argIdx + p.length);
                symbols.push({ name: p, kind: 'functionArg', range: new vscode.Range(pos, end), nameRange: new vscode.Range(pos, end) });
            }
        }
        for (const l of locals) {
            const localIdx = text.indexOf(l, funcBodyStart);
            if (localIdx >= 0) {
                const pos = document.positionAt(localIdx);
                const end = document.positionAt(localIdx + l.length);
                symbols.push({ name: l, kind: 'functionVar', range: new vscode.Range(pos, end), nameRange: new vscode.Range(pos, end) });
            }
        }
    }

    // label(NAME) definitions
    const labelRe = /\blabel\s*\(\s*([a-zA-Z_]\w*)\s*\)/g;
    while ((m = labelRe.exec(text)) !== null) {
        const nameStart = m.index + m[0].indexOf(m[1]);
        const pos = document.positionAt(nameStart);
        const end = document.positionAt(nameStart + m[1].length);
        symbols.push({
            name: m[1],
            kind: 'label',
            range: new vscode.Range(document.positionAt(m.index), document.positionAt(m.index + m[0].length)),
            nameRange: new vscode.Range(pos, end),
        });
    }

    // Function calls (including goto, instruction calls, etc.)
    const callRe = /\b([a-zA-Z_]\w*)\s*\(/g;
    const skipKeywords = new Set(['if', 'while', 'for', 'function', 'params', 'vars', 'var', 'return', 'compare', 'foreach']);
    while ((m = callRe.exec(text)) !== null) {
        const name = m[1];
        if (skipKeywords.has(name)) { continue; }
        const nameStart = m.index;
        const pos = document.positionAt(nameStart);
        const end = document.positionAt(nameStart + name.length);

        // Find closing paren for args range
        const argsStart = m.index + m[0].length;
        let depth = 1;
        let argsEnd = argsStart;
        for (let i = argsStart; i < text.length && depth > 0; i++) {
            if (text[i] === '(') { depth++; }
            else if (text[i] === ')') { depth--; if (depth === 0) { argsEnd = i; } }
        }

        calls.push({
            name,
            range: new vscode.Range(pos, end),
            argsRange: new vscode.Range(document.positionAt(argsStart), document.positionAt(argsEnd)),
        });
    }

    return { symbols, calls };
}

function parseVarList(document: vscode.TextDocument, content: string, offset: number, kind: 'param' | 'var', symbols: BehSymbol[]) {
    // Remove comments
    const cleaned = content.replace(/--.*$/gm, '');
    const varRe = /\b([a-zA-Z_]\w*)/g;
    let vm: RegExpExecArray | null;
    while ((vm = varRe.exec(cleaned)) !== null) {
        const absOffset = offset + vm.index;
        const pos = document.positionAt(absOffset);
        const end = document.positionAt(absOffset + vm[1].length);
        symbols.push({
            name: vm[1],
            kind,
            range: new vscode.Range(pos, end),
            nameRange: new vscode.Range(pos, end),
        });
    }
}

function findMatchingEnd(text: string, startIdx: number): number {
    // Simple depth counter for begin/end keywords
    let depth = 1;
    const endRe = /\b(function|repeat|if|foreach|compare|equal|larger|smaller)\b|\bend\b/g;
    endRe.lastIndex = startIdx;
    let em: RegExpExecArray | null;
    while ((em = endRe.exec(text)) !== null) {
        if (em[0] === 'end') {
            depth--;
            if (depth === 0) { return em.index; }
        } else {
            depth++;
        }
    }
    return -1;
}
