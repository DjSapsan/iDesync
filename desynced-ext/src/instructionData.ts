import * as path from 'path';
import * as fs from 'fs';

export interface InstructionArg {
    direction: 'in' | 'out' | 'exec';
    name: string;
    desc?: string;
    filter?: string;
    extra?: boolean;
}

export interface InstructionDef {
    name: string;
    desc?: string;
    category?: string;
    icon?: string;
    args?: InstructionArg[];
    exec_arg?: { index: number; label: string; desc?: string } | false;
}

export type InstructionMap = Record<string, InstructionDef>;

let cachedInstructions: InstructionMap | null = null;

export function getInstructions(extensionPath: string): InstructionMap {
    if (cachedInstructions) { return cachedInstructions; }
    const jsonPath = path.join(extensionPath, 'instructions-data.json');
    const raw = fs.readFileSync(jsonPath, 'utf-8');
    cachedInstructions = JSON.parse(raw) as InstructionMap;
    return cachedInstructions;
}
