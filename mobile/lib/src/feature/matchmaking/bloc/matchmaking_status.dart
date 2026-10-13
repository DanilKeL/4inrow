enum MatchmakingNotice { searchCancelled }

enum MatchmakingFailure {
  invalidCode,
  roomNotFound,
  roomFull,
  matchExpired,
  accountBusy,
  alreadyMatching,
  serverFull,
  moveNotSent,
  invalidServerResponse,
  connectionLost,
  generic,
  lobbyClosed,
}
