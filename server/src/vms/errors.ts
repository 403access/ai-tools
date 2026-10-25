/** Validation failure that the HTTP layer maps to a status code. */
export class VMValidationError extends Error {
  constructor(
    message: string,
    readonly status = 400,
  ) {
    super(message);
    this.name = "VMValidationError";
  }
}
