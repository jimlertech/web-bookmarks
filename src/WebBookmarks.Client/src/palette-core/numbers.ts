import type { PaletteEntry } from './types';

export type NumberSelection = { has: (index: number) => boolean };

// Parses a number-selection string like "1,3-5" into 1-based indices.
// Returns null if the whole string isn't a valid comma/range list.
export function parseNumberSelection(input: string): NumberSelection | null {
    const ranges: [number, number][] = [];
    const parts = input.split(',').map((s) => s.trim());
    for (const part of parts) {
        if (!part) continue;
        const rangeMatch = part.match(/^(\d+)\s*-\s*(\d+)$/);
        if (rangeMatch) {
            const lo = parseInt(rangeMatch[1], 10);
            const hi = parseInt(rangeMatch[2], 10);
            if (isNaN(lo) || isNaN(hi)) return null;
            ranges.push([Math.min(lo, hi), Math.max(lo, hi)]);
        } else if (/^\d+$/.test(part)) {
            const value = parseInt(part, 10);
            ranges.push([value, value]);
        } else {
            return null;
        }
    }
    return ranges.length > 0
        ? { has: (index) => ranges.some(([lo, hi]) => index >= lo && index <= hi) }
        : null;
}

// Splits a raw query into its search text and any trailing number selection
// (e.g. "docs 1,3" selects bookmark numbers 1 and 3).
export function detectNumberSelection(query: string): {
    searchPart: string;
    numberSelection: NumberSelection | null;
} {
    const match = query.match(/^(.*?)\s+([\d,\s-]+)$/);
    if (match) {
        return { searchPart: match[1], numberSelection: parseNumberSelection(match[2]) };
    }
    return { searchPart: query, numberSelection: null };
}

// Assigns sequential 1-based numbers to the bookmark rows in a display list,
// keyed by their index in that list.
export function assignBookmarkNumbers(displayList: PaletteEntry[]): Map<number, number> {
    const map = new Map<number, number>();
    let seq = 1;
    for (let i = 0; i < displayList.length; i++) {
        if (displayList[i].kind === 'bookmark') {
            map.set(i, seq++);
        }
    }
    return map;
}
