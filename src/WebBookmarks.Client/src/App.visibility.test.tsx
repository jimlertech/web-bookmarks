import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import App from './App';

const initialBookmark = {
    id: 1,
    name: 'Example bookmark',
    shortcut: '',
    description: '',
    url: 'https://example.invalid',
    urls: '',
    isVisible: true,
    bookmarkGroup: 'Examples',
    sortOrder: 0,
    profile: 'home',
    isFavorite: false,
};

let root: Root;
let host: HTMLDivElement;
let bookmark: typeof initialBookmark;
let updateResult: number;
let requests: { ids: number[]; isVisible: boolean }[];

const response = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

beforeEach(async () => {
    bookmark = { ...initialBookmark };
    updateResult = 1;
    requests = [];
    const saved = new Map<string, string>();
    vi.stubGlobal('localStorage', {
        getItem: (key: string) => saved.get(key) ?? null,
        setItem: (key: string, value: string) => saved.set(key, value),
        removeItem: (key: string) => saved.delete(key),
    });
    window.history.replaceState({}, '', '/?landing=1');
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
    vi.stubGlobal(
        'fetch',
        vi.fn(async (url: string, init?: RequestInit) => {
            if (url.endsWith('/profiles')) return response(['home']);
            if (url.endsWith('/bulk') && init?.method === 'PUT') {
                const body = JSON.parse(String(init.body)) as { ids: number[]; isVisible: boolean };
                requests.push(body);
                if (updateResult === 1) bookmark.isVisible = body.isVisible;
                return response({ updated: updateResult });
            }
            const includeHidden = new URL(url, window.location.origin).searchParams.has(
                'includeHidden',
            );
            return response(includeHidden || bookmark.isVisible ? [bookmark] : []);
        }),
    );
    host = document.createElement('div');
    document.body.append(host);
    root = createRoot(host);
    await act(async () => root.render(<App />));
});

afterEach(async () => {
    await act(async () => root.unmount());
    host.remove();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
});

function button(label: string): HTMLButtonElement {
    const element = host.querySelector<HTMLButtonElement>(`button[aria-label="${label}"]`);
    if (!element) throw new Error(`Missing button: ${label}`);
    return element;
}

it('toggles visibility and persists only the visibility field', async () => {
    await act(async () => button('Hide bookmark').click());
    expect(requests).toEqual([expect.objectContaining({ ids: [1], isVisible: false })]);
    expect(button('Show bookmark').closest('tr')?.className).toContain('row-hidden-bookmark');

    await act(async () => button('Show bookmark').click());
    expect(requests[1]).toEqual(expect.objectContaining({ ids: [1], isVisible: true }));
    expect(button('Hide bookmark').closest('tr')?.className).not.toContain('row-hidden-bookmark');
});

it('removes a newly hidden bookmark when the Hidden filter is off', async () => {
    await act(async () => button('Options').click());
    const checkbox = [...host.querySelectorAll('label')]
        .find((label) => label.textContent?.trim() === 'Hidden')
        ?.querySelector('input');
    if (!checkbox) throw new Error('Missing Hidden filter');
    await act(async () => checkbox.click());
    await act(async () => button('Hide bookmark').click());
    expect(host.querySelector('button[aria-label="Show bookmark"]')).toBeNull();
    expect(host.textContent).not.toContain('Example bookmark');
    expect(requests[0]).toEqual(expect.objectContaining({ ids: [1], isVisible: false }));
});

it('reports a missing bookmark without changing its visibility', async () => {
    updateResult = 0;
    await act(async () => button('Hide bookmark').click());
    expect(button('Hide bookmark')).toBeTruthy();
    expect(host.textContent).toContain('Bookmark could not be found.');
});
