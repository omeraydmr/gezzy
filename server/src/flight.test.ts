import assert from "node:assert/strict";
import test from "node:test";
import { appleTime, contentState, isWatchWindow, parseAeroDataBox, type Registration } from "./flight.ts";

const registration: Registration = {
  pushToken: "ab01", environment: "development", language: "tr", flightNumber: "TK1759", localDate: "2026-10-20",
  scheduledDeparture: "2026-10-20T04:40:00Z", scheduledArrival: "2026-10-20T09:15:00Z", seat: "14C", gate: null,
};

const response = [{
  status: "Expected",
  departure: { scheduledTime: { utc: "2026-10-20 04:40Z" }, revisedTime: { utc: "2026-10-20 05:25Z" }, gate: "F7", terminal: "I" },
  arrival: { scheduledTime: { utc: "2026-10-20 09:15Z" }, predictedTime: { utc: "2026-10-20 09:58Z" } },
}];

test("delay over 15 minutes becomes Delayed with minutes", () => {
  const status = parseAeroDataBox(response, new Date(registration.scheduledDeparture))!;
  assert.equal(status.phase, "delayed");
  const state = contentState(registration, status);
  assert.equal(state.status, "Rötarlı +45 dk");
  assert.equal(state.gate, "F7");
  assert.equal(state.seat, "14C");
  assert.equal(state.isDelayed, true);
  assert.equal(state.departure, appleTime(new Date("2026-10-20T05:25:00Z")));
  assert.equal(state.arrival, appleTime(new Date("2026-10-20T09:58:00Z")));
  assert.equal(contentState({ ...registration, language: "en" }, status).status, "Delayed +45 min");
});

test("apple reference time", () => {
  assert.equal(appleTime(new Date("2001-01-01T00:00:00Z")), 0);
});

test("on-time boarding and cancellation", () => {
  const boarding = parseAeroDataBox([{ ...response[0], status: "Boarding", departure: { ...response[0].departure, revisedTime: undefined } }],
    new Date(registration.scheduledDeparture))!;
  assert.equal(contentState(registration, boarding).status, "Biniş");
  const canceled = parseAeroDataBox([{ ...response[0], status: "Canceled" }], new Date(registration.scheduledDeparture))!;
  const state = contentState(registration, canceled);
  assert.equal(state.isCanceled, true);
  assert.equal(state.status, "İptal");
});

test("watch window", () => {
  assert.equal(isWatchWindow(registration, new Date("2026-10-19T20:00:00Z")), false);
  assert.equal(isWatchWindow(registration, new Date("2026-10-20T00:00:00Z")), true);
  assert.equal(isWatchWindow(registration, new Date("2026-10-20T16:00:00Z")), false);
});

test("empty or unrelated responses", () => {
  assert.equal(parseAeroDataBox([], new Date()), undefined);
  assert.equal(parseAeroDataBox({ message: "not found" }, new Date()), undefined);
});
