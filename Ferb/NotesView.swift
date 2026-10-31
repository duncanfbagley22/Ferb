import SwiftUI
import SwiftData

/// Settings → Notes: your own notes, newest edit first. Tap one to edit it, swipe to delete it.
struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var selection: Note?

    var body: some View {
        Group {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No notes yet",
                    systemImage: "note.text",
                    description: Text("Tap + to write one. Ideas, things to fix, or observations about a target all fit.")
                )
            } else {
                List {
                    ForEach(notes) { note in
                        Button { selection = note } label: { row(for: note) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    modelContext.delete(note)
                                    try? modelContext.save()
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New note", systemImage: "plus") { addNote() }
            }
        }
        .navigationDestination(item: $selection) { note in
            NoteEditorView(note: note)
        }
    }

    private func row(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.headline)
                .lineLimit(1)
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func addNote() {
        let note = Note()
        modelContext.insert(note)
        selection = note
    }
}

/// Edits one note, saving as you type. A note left blank is deleted when you leave.
private struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $note.body)
            .focused($isFocused)
            .padding(.horizontal)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: note.body) { note.updatedAt = .now }
            .onAppear {
                if note.isBlank { isFocused = true }
            }
            .onDisappear {
                if note.isBlank {
                    modelContext.delete(note)
                    try? modelContext.save()
                }
            }
    }
}
