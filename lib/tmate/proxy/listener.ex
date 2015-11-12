defmodule Tmate.Proxy.Listener do
  use GenServer

  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    :ok = :pg2.create(pg2_namespace)
    :ok = :pg2.join(pg2_namespace, self)
    {:ok, []}
  end

  defp pg2_namespace do
    {:tmate, :master}
  end

  def handle_info({:call, ref, from, args}, state) do
    worker = :poolboy.checkout(:proxy_endpoint_pool)
    _pid = spawn fn ->
      # TODO wrapping with an extra process kinda suck.
      # Figure out a way to do it better.
      result = try do
        Tmate.Proxy.Endpoint.call(worker, args)
      catch
        :exit, _ ->
          {:reply, {:error, :proc_exit}}
      rescue
        err ->
          Logger.warn(inspect(err))
          {:reply, {:error, :exception, err}}
      after
        :poolboy.checkin(:proxy_endpoint_pool, worker)
      end

      case result do
        {:reply, ret} -> send(from, {:reply, ref, ret})
      end
    end
    {:noreply, state}
  end
end
