import { HttpError } from "./errors.js";

const RESPONSE_FORMAT = "structured-v1";
const CONTEXT_KEYS = ["choices", "questionType", "selectedChoices"];
const NUMBER_ARRAY = {
  type: "array",
  items: { type: "integer", minimum: 1, maximum: 20 },
  maxItems: 20,
};

function generationConfiguration(kind, structured = false, retry = false) {
  const configuration = {
    maxOutputTokens: (kind === "answer" ? 2048 : 4096) * (retry ? 2 : 1),
    thinkingConfig: { thinkingLevel: "low" },
  };
  if (structured) {
    configuration.responseMimeType = "application/json";
    configuration.responseJsonSchema = responseSchema(kind);
  }
  return configuration;
}

function responseSchema(kind) {
  const properties = {
    questionType: { type: "string", enum: ["multipleChoice", "shortAnswer"] },
    choices: NUMBER_ARRAY,
    selectedChoices: NUMBER_ARRAY,
  };
  if (kind === "answer") {
    properties.answer = { type: "string", description: "객관식은 빈 문자열, 단답형은 정답만" };
  } else {
    properties.coreExplanation = { type: "string", minLength: 1 };
    properties.recommendedLearning = { type: "string", minLength: 1 };
    properties.wrongChoiceReasons = {
      type: "array",
      maxItems: 20,
      items: {
        type: "object",
        properties: {
          choice: { type: "integer", minimum: 1, maximum: 20 },
          reason: { type: "string", minLength: 1 },
        },
        required: ["choice", "reason"],
        additionalProperties: false,
      },
    };
  }
  return { type: "object", properties, required: Object.keys(properties).sort(), additionalProperties: false };
}

function answerContextHeader(value) {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || value.length > 1024) {
    throw new HttpError(400, "invalid_request", "invalid answer context");
  }
  let context;
  try {
    context = JSON.parse(value);
  } catch {
    throw new HttpError(400, "invalid_request", "invalid answer context");
  }
  if (!validContext(context) || JSON.stringify(Object.keys(context).sort()) !== JSON.stringify(CONTEXT_KEYS)) {
    throw new HttpError(400, "invalid_request", "invalid answer context");
  }
  return context;
}

function validContext(context) {
  if (!context || typeof context !== "object" || !Array.isArray(context.choices) || !Array.isArray(context.selectedChoices)) {
    return false;
  }
  if (context.questionType === "shortAnswer") {
    return context.choices.length === 0 && context.selectedChoices.length === 0;
  }
  return context.questionType === "multipleChoice" && context.choices.length >= 2 && context.choices.length <= 20
    && context.choices.every((choice) => Number.isInteger(choice) && choice >= 1 && choice <= 20)
    && new Set(context.choices).size === context.choices.length && context.selectedChoices.length > 0
    && new Set(context.selectedChoices).size === context.selectedChoices.length
    && context.selectedChoices.every((choice) => context.choices.includes(choice));
}

function sameNumbers(left, right) {
  return left.length === right.length && left.every((number) => right.includes(number));
}

function nonempty(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function validPayload(payload, kind, expected) {
  if (!validContext(payload)) return false;
  if (kind === "answer") {
    return typeof payload.answer === "string"
      && (payload.questionType === "multipleChoice" ? payload.answer === "" : nonempty(payload.answer));
  }
  if (!nonempty(payload.coreExplanation) || !nonempty(payload.recommendedLearning)
    || !Array.isArray(payload.wrongChoiceReasons)) return false;
  if (expected && (payload.questionType !== expected.questionType
    || !sameNumbers(payload.choices, expected.choices)
    || !sameNumbers(payload.selectedChoices, expected.selectedChoices))) return false;
  const others = payload.choices.filter((choice) => !payload.selectedChoices.includes(choice));
  const reasons = payload.wrongChoiceReasons;
  return reasons.length === others.length && reasons.every((item) => item && others.includes(item.choice) && nonempty(item.reason))
    && new Set(reasons.map((item) => item.choice)).size === others.length;
}

// HTTP 200만으로 과금하지 않는다. 완결성과 형식을 확인한 뒤에만 예약을 확정한다.
function validateGeneration(responseText, kind, structured, expected) {
  let response;
  try {
    response = JSON.parse(responseText);
  } catch {
    throw new HttpError(502, "invalid_response", "AI response could not be verified");
  }
  const candidate = response?.candidates?.[0];
  if (candidate?.finishReason === "MAX_TOKENS") {
    throw new HttpError(502, "incomplete_response", "AI response was incomplete");
  }
  if (candidate?.finishReason !== "STOP" || !Array.isArray(candidate.content?.parts)) {
    throw new HttpError(502, "invalid_response", "AI response could not be verified");
  }
  const text = candidate.content.parts.filter((part) => part && part.thought !== true && typeof part.text === "string")
    .map((part) => part.text).join("\n").trim();
  if (!text) throw new HttpError(502, "invalid_response", "AI response could not be verified");
  if (!structured) return;
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new HttpError(502, "invalid_response", "AI response could not be verified");
  }
  if (!validPayload(payload, kind, expected)) {
    throw new HttpError(502, "invalid_response", "AI response could not be verified");
  }
}

export { RESPONSE_FORMAT, answerContextHeader, generationConfiguration, validateGeneration };
