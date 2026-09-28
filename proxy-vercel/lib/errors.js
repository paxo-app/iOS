class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
  }
}

function asHttpError(error, status = 500, code = "internal_error", message = "internal error") {
  if (error instanceof HttpError) return error;
  return new HttpError(status, code, message);
}

export { HttpError, asHttpError };
