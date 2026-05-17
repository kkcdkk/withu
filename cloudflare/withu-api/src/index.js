const OPENAI_IMAGE_MODEL = "gpt-image-1";
const OPENAI_IMAGE_GENERATIONS_ENDPOINT = "https://api.openai.com/v1/images/generations";
const OPENAI_IMAGE_EDITS_ENDPOINT = "https://api.openai.com/v1/images/edits";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/" || url.pathname === "/health") {
      return Response.json({
        ok: true,
        service: "withu-api",
        openai_configured: Boolean(env.OPENAI_API_KEY)
      });
    }

    if (url.pathname === "/generate") {
      if (request.method !== "POST") {
        return jsonError("Method not allowed", 405);
      }

      return generateImage(request, env);
    }

    return Response.json(
      { detail: "Not found" },
      { status: 404 }
    );
  }
};

async function generateImage(request, env) {
  if (!env.OPENAI_API_KEY) {
    return jsonError("OPENAI_API_KEY secret is not configured.", 503);
  }

  let input;
  try {
    input = await request.json();
  } catch {
    return jsonError("Request body must be JSON.", 400);
  }

  if (typeof input.prompt !== "string" || input.prompt.trim() === "") {
    return jsonError("prompt is required.", 400);
  }

  let openAIResponse;
  try {
    openAIResponse = input.reference_image_base64
      ? await editImage(input, env.OPENAI_API_KEY)
      : await generateImageFromPrompt(input, env.OPENAI_API_KEY);
  } catch (error) {
    return jsonError(error.message, 400);
  }

  const text = await openAIResponse.text();
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    payload = null;
  }

  if (!openAIResponse.ok) {
    return jsonError(payload?.error?.message ?? text, openAIResponse.status);
  }

  const image = payload?.data?.[0];
  if (!image?.b64_json) {
    return jsonError("OpenAI response did not include image data.", 502);
  }

  return Response.json({
    image_base64: image.b64_json,
    seed: 0,
    revised_prompt: image.revised_prompt ?? null
  });
}

function generateImageFromPrompt(input, apiKey) {
  return fetch(OPENAI_IMAGE_GENERATIONS_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: OPENAI_IMAGE_MODEL,
      prompt: input.prompt,
      quality: normalizeQuality(input.quality),
      size: normalizeSize(input.width, input.height),
      n: 1
    })
  });
}

function editImage(input, apiKey) {
  const form = new FormData();
  form.append("model", OPENAI_IMAGE_MODEL);
  form.append("prompt", input.prompt);
  form.append("quality", normalizeQuality(input.quality));
  form.append("size", normalizeSize(input.width, input.height));
  form.append("n", "1");
  form.append("image", base64ToBlob(input.reference_image_base64), "reference.png");

  return fetch(OPENAI_IMAGE_EDITS_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`
    },
    body: form
  });
}

function normalizeQuality(quality) {
  return ["low", "medium", "high", "auto"].includes(quality) ? quality : "medium";
}

function normalizeSize(width, height) {
  const size = `${width}x${height}`;
  return ["1024x1024", "1024x1536", "1536x1024", "auto"].includes(size)
    ? size
    : "1024x1024";
}

function jsonError(detail, status) {
  return Response.json({ detail }, { status });
}

function base64ToBlob(value) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error("reference_image_base64 is invalid.");
  }

  const cleanValue = value.includes(",") ? value.split(",").at(-1) : value;
  try {
    const bytes = Uint8Array.from(atob(cleanValue), (char) => char.charCodeAt(0));
    return new Blob([bytes], { type: "image/png" });
  } catch {
    throw new Error("reference_image_base64 is invalid.");
  }
}
