defmodule GraceJobs.Scrapers.ComputerUse.NullHost do
  @moduledoc """
  No-op browser host. Returns a tiny solid-colour PNG for screenshots and
  swallows other actions. Useful for tests and as a placeholder when no
  real browser is wired up yet.
  """

  # 1x1 transparent PNG
  @pixel "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkAAIAAAoAAv/lxKUAAAAASUVORK5CYII="

  def screenshot, do: {:ok, @pixel}
  def click(_x, _y), do: :ok
  def type(_text), do: :ok
end
