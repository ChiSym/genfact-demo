const _tokenizer_config_path = "$(@__DIR__)/../../resources/tokenizer_configs/llama3pt1_8b.json"
function __init__()
    _jinja2 = pyimport("jinja2")
    _jinja2sandbox = pyimport("jinja2.sandbox")
    _jinja2exceptions = pyimport("jinja2.exceptions")

    # jac: I based this code on
    # https://github.com/huggingface/transformers/blob/a24a9a66f446dcb9277e31d16255536c5ce27aa6/src/transformers/tokenization_utils_base.py#L1897
    # but heavily stripped back on the code for simplicity's sake.
    # We don't need to handle automated tool injection or the other complexity Hugging Face supports.
    #
    # jac: I think  we can avoid copying the whole AssistantTracker code from
    # https://github.com/huggingface/transformers/blob/v4.43.1/src/transformers/tokenization_utils_base.py#L1921
    # because it seems to focus on tracking token indices. Because we don't actually need to tokenize the prompt
    # on our side, this is a moot point.
    py"""
import json

def raise_exception(message):
    raise TemplateError(message)

# Define alternate tojson function so that jinja2 doesn't HTML-escape things that shouldn't be.
# https://github.com/huggingface/transformers/blob/782bfffb2e4dfb5bbe7940429215d794f4434172/src/transformers/tokenization_utils_base.py#L1916
def tojson(x, ensure_ascii=False, indent=None, separators=None, sort_keys=False):
    return json.dumps(x, ensure_ascii=ensure_ascii, indent=indent, separators=separators, sort_keys=sort_keys)
"""

    _tokenizer_config = open(_tokenizer_config_path) do file
    JSON3.read(read(file, String))
end
    _template_params = Dict("bos_token" => _tokenizer_config["bos_token"])
    _chat_template = _tokenizer_config["chat_template"]

    env = _jinja2sandbox.ImmutableSandboxedEnvironment(trim_blocks=true, lstrip_blocks=true, extensions=[])
    env.filters["tojson"] = py"tojson"
    env.globals["raise_exception"] = py"raise_exception"
    global _compiled_chat_template = env.from_string(_chat_template)
end


@doc """Format the prompt as a user chat message.

This assumes the Genparse server is using a chat-trained model with a chat template."""
function prompt_as_user_chat_msg(prompt)
    _compiled_chat_template.render(
        messages=[Dict("role" => "user", "content" => prompt)],
        tools=py"None",
    )
end

export prompt_as_user_chat_msg
