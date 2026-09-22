namespace CrestCore.Domain;

/// Whether a Quick Window request changes, and whether the move teaches the
/// link preferences which Space the page's site belongs in.
public readonly record struct QuickWindowRetarget(bool Revises, bool RemembersSpace);
