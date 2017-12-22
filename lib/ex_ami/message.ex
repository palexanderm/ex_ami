defmodule ExAmi.Message do
  require Logger

  @eol  "\r\n"
  # @eom  "\r\n\r\n"

  defmodule Message do
    defstruct attributes: %{}, variables: %{}
    def new, do: %__MODULE__{}
    def new(attributes, variables),
      do: %__MODULE__{attributes: attributes, variables: variables}
    def new(opts), do: struct(new(), opts)
  end

  def new_message, do: Message.new()
  def new_message(attributes, variables), do: Message.new(attributes, variables)

  def new_action(name) do
    action_id =
      :os.timestamp
      |> Tuple.to_list
      |> Enum.map(&(Integer.to_string(&1)))
      |> Enum.reduce("", &(&2 <> &1))

    set_all(new_message(), [{"Action", name}, {"ActionID", action_id}])
  end

  def new_action(name, attributes) do
    name
    |> new_action()
    |> set_all(attributes)
  end

  def new_action(name, attributes, variables) do
    name
    |> new_action()
    |> set_all(attributes)
    |> set_all_variables(variables)
  end

  def get(%Message{attributes: attributes}, key) do
    case Map.fetch(attributes, key) do
      {:ok, value} -> {:ok, value}
      _ -> :notfound
    end
  end

  def get_variable(%Message{variables: variables}, key) do
    case Map.fetch variables, key do
      {:ok, value} -> {:ok, value}
      _ -> :notfound
    end
  end

  def set(key, value) do
    set(new_message(), key, value)
  end

  def set(%Message{} = message, key, value) do
    message.attributes
    |> Map.put(key, value)
    |> new_message(message.variables)
  end

  def set_all(%Message{} = message, attributes) do
    Enum.reduce attributes, message, fn({key, value}, acc) -> set(acc, key, value) end
  end

  def set_variable(%Message{variables: variables, attributes: attributes}, key, value),
    do: new_message(attributes, Map.put(variables, key, value))

  def set_all_variables(%Message{} = message, variables) do
    Enum.reduce(variables, message, fn({key,value}, acc) -> set_variable(acc, key, value) end)
  end

  def marshall(%Message{attributes: attributes, variables: variables}) do
    Enum.reduce(Map.to_list(attributes), "", fn({k,v}, acc) -> marshall(acc, k, v) end) <>
    Enum.reduce(Map.to_list(variables), "", fn({k,v}, acc) -> marshall_variable(acc, k, v) end) <>
    @eol
  end
  def marshall(key, value), do: key <> ": " <> value <> @eol
  def marshall(acc, key, value), do: acc <> marshall(key, value)

  def marshall_variable(key, value), do: marshall("Variable", key <> "=" <> value)
  def marshall_variable(acc, key, value), do: acc <> marshall("Variable", key <> "=" <> value)

  def explode_lines(text), do: String.split(text, "\r\n", trim: true)

  def format_log(%{attributes: attributes}) do
    cond do
      value = Map.get(attributes, "Event") ->
        format_log("Event", value, attributes)
      value = Map.get(attributes, "Response") ->
        format_log("Response", value, attributes)
      true -> {:error, :notfound}
    end
  end
  def format_log(key, value, attributes) do
    attributes
    |> Map.delete(key)
    |> Map.to_list
    |> Enum.reduce(key <> ": \"" <> value <> "\"", fn({k,v}, acc) ->
      acc <> ", " <> k <> ": \"" <> v <> "\""
    end)
  end

  def unmarshall(text) do
    Enum.reduce explode_lines(text), new_message(), fn(line, acc) ->
      line
      |> String.split(":", trim: true, parts: 2)
      |> Enum.map(&(String.trim(&1)))
      |> _unmarshall(acc)
    end
  end
  defp _unmarshall([key,value], %Message{} = message), do: set(message, key, value)
  defp _unmarshall([], %Message{} = message), do: message
  defp _unmarshall(["ReportBlock"], %Message{} = message), do: message
  defp _unmarshall(other, %Message{} = message) do
    Logger.error("_unmarshall invalid input #{inspect other}")
    message
  end

  def is_response(%Message{} = message), do: is_type(message, "Response")
  def is_event(%Message{} = message), do: is_type(message, "Event")

  def is_response_success(%Message{} = message) do
    {:ok, value} = get(message, "Response")
    value == "Success"
  end

  def is_response_error(%Message{} = message) do
    {:ok, value} = get(message, "Response")
    value == "Error"
  end

  def is_response_complete(%Message{} = message) do
    case get(message, "Message") do
      :notfound -> true
      {:ok, response_text} ->
        !String.match?(response_text, ~r/ollow/)
    end
  end

  # def is_event_last_for_response(%Message{} = message) do
  #   case get(message, "EventList") do
  #     :notfound ->
  #     {:ok, response_text} ->
  #       String.match?(response_text, ~r/omplete/)
  #   end
  # end
  def is_event_last_for_response(%Message{} = message) do
    with :notfound <- get(message, "EventList"),
         :notfound <- get(message, "Event") do
      false
    else
      {:ok, response_text} ->
        String.match?(response_text, ~r/omplete/)
      _ ->
        false
    end
  end

  defp is_type(%Message{} = message, type) do
    case get(message, type) do
      {:ok, _} -> true
      _ -> false
    end
  end

end
