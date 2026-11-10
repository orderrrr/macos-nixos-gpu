# Pi Session Viewing

Language for browsing a Pi conversation without interacting with the agent.

## Language

**Session**:
A Pi conversation history associated with a working directory, including its alternate branches.

**Snapshot**:
The session history available at the moment it is selected for viewing, independent of later changes.

**Transcript**:
The ordered user and assistant messages, with tool summaries, on the session's selected branch.
_Avoid_: Chat input, terminal

**Tool summary**:
A concise account of one recorded tool use, including its known outcome.

**Tool preview**:
The recorded inputs, output, and additional result data of one tool use, whether completed, failed,
or unfinished. It is independent of today's files and does not repeat the operation.

**Recorded diff**:
The change reported by a successful tool result at execution time, rather than its proposed change
or the file's current difference from Git.
_Avoid_: Working-tree diff, proposed diff

**Recorded write content**:
The full text requested by a successful file-write operation. It contains no previous version and
is not an independent snapshot of the resulting file.
