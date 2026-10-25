/**
 * Bun.serve has one WebSocket handler for every route, so both terminal and
 * remote-desktop upgrades share this discriminated data shape.
 */
export interface TerminalSocketData {
  kind: "terminal";
  url: string;
  authorization: string;
  terminalID: string;
  location: string;
  upstream?: WebSocket;
  closed?: boolean;
}

export interface RemoteSocketData {
  kind: "remote";
  closed?: boolean;
}

export type HubSocketData = TerminalSocketData | RemoteSocketData;
