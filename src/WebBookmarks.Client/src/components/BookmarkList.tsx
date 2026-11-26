import type { BookmarkGroup as BookmarkGroupType, WebBookmarksItem } from '../types';
import BookmarkGroupComponent from './BookmarkGroup';

interface Props {
    groups: BookmarkGroupType[];
    onEdit: (item: WebBookmarksItem) => void;
    onDelete: (item: WebBookmarksItem) => void;
    onReorder: (groupName: string, activeId: number, overId: number) => void;
    onToggleFavorite: (item: WebBookmarksItem) => void;
    onToggleVisibility: (item: WebBookmarksItem) => void;
    visibilityPending: Set<number>;
    conflictIds: Set<number>;
    editMode: boolean;
    showVisibilityButtons: boolean;
}

// Renders the displayed bookmark groups. Each group is its own dnd-kit sortable table.
export default function BookmarkList({
    groups,
    onEdit,
    onDelete,
    onReorder,
    onToggleFavorite,
    onToggleVisibility,
    visibilityPending,
    conflictIds,
    editMode,
    showVisibilityButtons,
}: Props) {
    return (
        <>
            {groups.map((g) => (
                <BookmarkGroupComponent
                    key={g.name}
                    group={g}
                    onEdit={onEdit}
                    onDelete={onDelete}
                    onReorder={onReorder}
                    onToggleFavorite={onToggleFavorite}
                    onToggleVisibility={onToggleVisibility}
                    visibilityPending={visibilityPending}
                    conflictIds={conflictIds}
                    editMode={editMode}
                    showVisibilityButtons={showVisibilityButtons}
                />
            ))}
        </>
    );
}
