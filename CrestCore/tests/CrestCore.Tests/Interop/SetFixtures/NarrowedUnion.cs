using CrestCore.Contracts;

namespace CrestCore.Tests.Narrowed;

/// Moves among the intents: a query holds one of them and no other intent.
public abstract record Move(Guid Piece) : Intent;

public sealed record Slide(Guid Piece, int Squares) : Move(Piece);

public sealed record Jump(Guid Piece) : Move(Piece);

public sealed record Resign : Intent;

/// Whether the move is legal.
public sealed record MoveCheck(Move Move) : Query<bool>;
