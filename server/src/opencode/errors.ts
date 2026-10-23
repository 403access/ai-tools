export interface OpenCodeLocation {
  url: string;
  password: string;
}

export class OpenCodeError extends Error {
  readonly status?: number;

  constructor(message: string, status?: number) {
    super(message);
    this.name = "OpenCodeError";
    this.status = status;
  }

  get unauthorized(): boolean {
    return this.status === 401 || this.status === 403;
  }
}

export class GoUsageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GoUsageError";
  }
}
