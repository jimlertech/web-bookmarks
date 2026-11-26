import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import BookmarkGroup from './BookmarkGroup';
import type { WebBookmarksItem } from '../types';

const item: WebBookmarksItem = {
    id: 1,
    name: 'Example bookmark',
    shortcut: '_example',
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
let availableWidth: number;
let labelWidth: number;
let notifyResize: () => void;
let media: MediaQueryList & { matches: boolean };
let shortcutDisconnect: ReturnType<typeof vi.fn>;

beforeEach(() => {
    availableWidth = 144;
    labelWidth = 48;
    media = Object.assign(new EventTarget(), {
        matches: true,
        media: '(min-width: 481px) and (max-width: 768px)',
        onchange: null,
        addListener: vi.fn(),
        removeListener: vi.fn(),
    });
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
    vi.stubGlobal(
        'matchMedia',
        vi.fn(() => media),
    );
    vi.stubGlobal(
        'ResizeObserver',
        class {
            constructor(private callback: ResizeObserverCallback) {}
            observe(target: Element) {
                if (target.classList.contains('shortcut-label')) {
                    notifyResize = () => this.callback([], this);
                    shortcutDisconnect = this.disconnect;
                }
            }
            unobserve() {}
            disconnect = vi.fn();
        },
    );
    vi.spyOn(Element.prototype, 'getBoundingClientRect').mockImplementation(function (
        this: Element,
    ) {
        const width = this.classList.contains('shortcut-wrap')
            ? availableWidth
            : this.classList.contains('shortcut-label')
              ? labelWidth
              : this.classList.contains('bookmark-row-actions')
                ? 88
                : 0;
        return new DOMRect(0, 0, width, 20);
    });
    host = document.createElement('div');
    const style = document.createElement('style');
    style.textContent = '.shortcut-wrap { column-gap: 8px; }';
    document.head.append(style);
    document.body.append(host);
    root = createRoot(host);
    act(() =>
        root.render(
            <BookmarkGroup
                group={{ name: 'Examples', items: [item] }}
                onEdit={vi.fn()}
                onDelete={vi.fn()}
                onReorder={vi.fn()}
                onToggleFavorite={vi.fn()}
                onToggleVisibility={vi.fn()}
                visibilityPending={new Set()}
                conflictIds={new Set()}
                editMode
            />,
        ),
    );
});

afterEach(() => {
    act(() => root.unmount());
    host.remove();
    document.head.querySelector('style')?.remove();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
});

it('hides a shortcut that does not fit and restores it when space returns', () => {
    const label = host.querySelector('.shortcut-label')!;
    expect(label.classList.contains('shortcut-does-not-fit')).toBe(false);

    labelWidth = 49;
    act(() => notifyResize());
    expect(label.classList.contains('shortcut-does-not-fit')).toBe(true);

    availableWidth = 145;
    act(() => notifyResize());
    expect(label.classList.contains('shortcut-does-not-fit')).toBe(false);
});

it('removes the fit restriction outside tablet widths and cleans up its observer', () => {
    const label = host.querySelector('.shortcut-label')!;
    availableWidth = 100;
    act(() => notifyResize());
    expect(label.classList.contains('shortcut-does-not-fit')).toBe(true);

    media.matches = false;
    act(() => media.dispatchEvent(new Event('change')));
    expect(label.classList.contains('shortcut-does-not-fit')).toBe(false);

    act(() => root.unmount());
    expect(shortcutDisconnect).toHaveBeenCalledOnce();
});
