import * as vscode from 'vscode';
import { getInstructions } from './instructionData';
import { BehCompletionProvider } from './providers/completion';
import { BehHoverProvider } from './providers/hover';
import { BehDocumentSymbolProvider } from './providers/symbols';
import { BehDefinitionProvider } from './providers/definition';
import { BehSignatureHelpProvider } from './providers/signatureHelp';
import { createDiagnostics } from './providers/diagnostics';

const BEH_SELECTOR: vscode.DocumentSelector = { language: 'beh', scheme: 'file' };

export function activate(context: vscode.ExtensionContext) {
    const instructions = getInstructions(context.extensionPath);

    // Completion (IntelliSense)
    context.subscriptions.push(
        vscode.languages.registerCompletionItemProvider(
            BEH_SELECTOR,
            new BehCompletionProvider(instructions),
        )
    );

    // Hover
    context.subscriptions.push(
        vscode.languages.registerHoverProvider(
            BEH_SELECTOR,
            new BehHoverProvider(instructions),
        )
    );

    // Document symbols (outline / breadcrumbs)
    context.subscriptions.push(
        vscode.languages.registerDocumentSymbolProvider(
            BEH_SELECTOR,
            new BehDocumentSymbolProvider(),
        )
    );

    // Go-to-definition
    context.subscriptions.push(
        vscode.languages.registerDefinitionProvider(
            BEH_SELECTOR,
            new BehDefinitionProvider(),
        )
    );

    // Signature help (parameter hints)
    context.subscriptions.push(
        vscode.languages.registerSignatureHelpProvider(
            BEH_SELECTOR,
            new BehSignatureHelpProvider(instructions),
            '(', ','
        )
    );

    // Diagnostics
    const diagnosticCollection = vscode.languages.createDiagnosticCollection('beh');
    context.subscriptions.push(diagnosticCollection);

    const runDiagnostics = (doc: vscode.TextDocument) => {
        if (doc.languageId === 'beh') {
            createDiagnostics(doc, instructions, diagnosticCollection);
        }
    };

    // Run on open, save, and change
    context.subscriptions.push(
        vscode.workspace.onDidOpenTextDocument(runDiagnostics),
        vscode.workspace.onDidSaveTextDocument(runDiagnostics),
        vscode.workspace.onDidChangeTextDocument(e => runDiagnostics(e.document)),
    );

    // Run on already-open documents
    vscode.workspace.textDocuments.forEach(runDiagnostics);
}

export function deactivate() {}
