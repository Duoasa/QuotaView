"""Synthetic, immutable bridge policy. No network, AX, TCC, or app access.

A synthetic transactional grant models a REQUIRED future native primitive. It
is not an installed Codex capability. With no such grant, automatic close fails
closed; two ordinary AX reads do not eliminate read/press TOCTOU.
"""
from __future__ import annotations
from dataclasses import dataclass, replace
from enum import Enum
import hashlib
import json


def digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


class Permission(Enum):
    DISABLED = "disabled"
    DENIED = "denied"
    GRANTED = "granted"
    REVOKED = "revoked"


class NativeBehavior(Enum):
    PURE_DISMISS = "pureDismiss"
    SKIP = "skip"
    SEND = "send"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class Scope:
    process: int
    incarnation: str
    build: str
    owner: str
    epoch: int
    host: str
    conversation: str
    turn: str
    entity_key: str


@dataclass(frozen=True)
class Member:
    source: str
    index: int
    native_id: str
    question_hash: str

    def valid(self) -> bool:
        if not isinstance(self.source, str) or not self.source or type(self.index) is not int:
            return False
        expected = json.dumps(["request_user_input_async", self.source, self.index],
                              ensure_ascii=False, separators=(",", ":"))
        return (0 <= self.index < 256 and self.native_id == expected
                and valid_hash(self.question_hash))


def valid_hash(value: str) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


@dataclass(frozen=True)
class Selection:
    scope: Scope
    selected_item: str
    generation: int
    members: tuple[Member, ...]
    complete: bool = True
    fresh: bool = True
    owner_proven: bool = True
    resource_revoked: bool = False

    @property
    def key(self) -> tuple:
        # One selected group can append questions from MULTIPLE agent messages.
        # Membership/order/generation are part of identity, not one source ID.
        return (self.scope, self.selected_item, self.generation, self.members)

    def valid(self) -> bool:
        s = self.scope
        return (type(s.process) is int and s.process > 0 and type(s.epoch) is int and s.epoch > 0
                and all(isinstance(v, str) and bool(v) for v in
                        (s.incarnation, s.build, s.owner, s.host, s.conversation, s.turn, s.entity_key,
                         self.selected_item))
                and type(self.generation) is int and self.generation >= 0
                and self.complete and self.fresh and self.owner_proven and not self.resource_revoked
                and 0 < len(self.members) <= 256 and all(m.valid() for m in self.members)
                and len({m.native_id for m in self.members}) == len(self.members)
                # The actual native selected item is itself a canonical member.
                and self.selected_item in {m.native_id for m in self.members})


@dataclass(frozen=True)
class Answer:
    member: Member
    value_hash: str


@dataclass(frozen=True)
class APICapability:
    selection: Selection
    can_submit: bool = True
    fresh: bool = True
    resource_revoked: bool = False


@dataclass(frozen=True)
class PureDismissSemantics:
    behavior: NativeBehavior = NativeBehavior.UNKNOWN
    native_contract_verified: bool = False
    sends_answer: bool = True
    preserves_other_selections: bool = False
    closes_selected_group: bool = False
    # An attribute/name is diagnostic only; never used to infer semantics.
    attribute: str = ""

    def valid(self) -> bool:
        return (self.behavior is NativeBehavior.PURE_DISMISS and self.native_contract_verified
                and not self.sends_answer and self.preserves_other_selections
                and self.closes_selected_group)


@dataclass(frozen=True)
class AXProof:
    selection: Selection
    element: str
    element_generation: int
    drafts: tuple[Answer, ...]
    draft_revision: int
    accepted_baseline_revision: int
    semantics: PureDismissSemantics
    exact_native_identity: bool = False
    complete_drafts: bool = False
    focused_selection: bool = False
    editing: bool = True
    autosend_pending: bool = True
    fresh: bool = True


@dataclass(frozen=True)
class SyntheticCASGrant:
    """Future contract premise ONLY, issued/consumed by the fake smoke adapter.

    It models native atomic identity+membership+draft compare-and-dismiss. No
    real lease API exists or is asserted by this prototype. A Boolean in an AX
    observation is NOT sufficient to grant this in a production adapter.
    """
    selection_key: tuple
    element: str
    element_generation: int
    draft_revision: int
    baseline: tuple[Answer, ...]
    nonce: str
    expires_tick: int
    transactional_native_guard: bool = False


@dataclass(frozen=True)
class ClosedProof:
    selection: Selection
    current_scope: Scope
    observed_tick: int
    target_selected_group_absent: bool
    remaining_unanswered_keys: frozenset[tuple]
    exact_native_identity: bool = False
    complete: bool = False
    navigation_unchanged: bool = False
    fresh: bool = False


@dataclass(frozen=True)
class Record:
    selection: Selection
    eligible: bool = True
    api_reserved: bool = False
    api_claimed: bool = False
    delivered: bool = False
    api_unknown: bool = False
    api_answers: tuple[Answer, ...] = ()
    accepted_answers: tuple[Answer, ...] = ()
    dismiss_reserved: bool = False
    dismiss_claimed: bool = False
    dismiss_unknown: bool = False
    dismiss_tick: int = -1
    renderer_closed: bool = False

    @property
    def answered(self) -> bool:
        return (len(self.accepted_answers) == len(self.selection.members)
                and {a.member for a in self.accepted_answers} == set(self.selection.members))


@dataclass(frozen=True)
class State:
    records: tuple[Record, ...] = ()
    focus_key: tuple | None = None
    permission: Permission = Permission.DISABLED
    consumed_grants: frozenset[str] = frozenset()
    # Stable logical question identity survives selection/owner/epoch changes.
    api_reserved_members: frozenset[tuple] = frozenset()

    def record(self, key: tuple) -> Record | None:
        return next((r for r in self.records if r.selection.key == key), None)


@dataclass(frozen=True)
class Intent:
    kind: str  # ONLY apiSend or pureDismiss, never an actual platform operation.
    key: tuple
    answers: tuple[Answer, ...] = ()
    ax_proof: AXProof | None = None
    grant: SyntheticCASGrant | None = None


@dataclass(frozen=True)
class Decision:
    state: State
    intents: tuple[Intent, ...] = ()
    status: str = "handoff"


def update(state: State, record: Record) -> State:
    return replace(state, records=tuple(record if r.selection.key == record.selection.key else r
                                        for r in state.records))


def observe(state: State, selection: Selection) -> Decision:
    if not selection.valid():
        return Decision(state, status="unprovenSelection")
    old = state.record(selection.key)
    records = tuple(replace(r, eligible=False)
                    if (r.selection.scope.host == selection.scope.host
                        and r.selection.scope.conversation == selection.scope.conversation
                        and r.selection.key != selection.key) else r
                    for r in state.records)
    state = replace(state, records=records, focus_key=selection.key)
    if old is None:
        if len(records) >= 64:
            return Decision(state, status="resourceLimit")
        prior = {a.member: a for r in records if r.selection.scope == selection.scope
                 for a in r.accepted_answers}
        baseline = tuple(prior[m] for m in selection.members if m in prior)
        state = replace(state, records=records + (Record(selection, accepted_answers=baseline),))
    else:
        # Reobservation does not erase an at-most-once reservation/unknown result.
        state = update(state, replace(old, selection=selection, eligible=True))
    return Decision(state, status="observed")


def permission(state: State, value: Permission) -> Decision:
    # Pure explicit input only: no trust dialog, settings launch, or permission ask.
    return Decision(replace(state, permission=value), status="permissionChanged")


def revoke(state: State, key: tuple) -> Decision:
    record = state.record(key)
    if record is None:
        return Decision(state)
    return Decision(update(state, replace(record, eligible=False)), status="revoked")


def capability_matches(record: Record, capability: APICapability) -> bool:
    return (record.eligible and capability.can_submit and capability.fresh
            and not capability.resource_revoked and capability.selection.valid()
            and record.selection.key == capability.selection.key)


def complete_answers(selection: Selection, answers: tuple[Answer, ...]) -> bool:
    return (len(answers) == len(selection.members)
            and tuple(a.member for a in answers) == selection.members
            and all(valid_hash(a.value_hash) for a in answers))


def confirm(state: State, capability: APICapability, answers: tuple[Answer, ...]) -> Decision:
    record = state.record(capability.selection.key)
    if record is None:
        return Decision(state)
    accepted_members = {a.member for a in record.accepted_answers}
    pending = tuple(m for m in record.selection.members if m not in accepted_members)
    logical_keys = frozenset((record.selection.scope.host, record.selection.scope.conversation,
                              record.selection.scope.turn, a.member.native_id)
                             for a in answers)
    if (record.api_reserved or record.renderer_closed or record.answered or not pending
            or not capability_matches(record, capability)
            or tuple(a.member for a in answers) != pending
            or any(not valid_hash(a.value_hash) for a in answers)
            or bool(logical_keys & state.api_reserved_members)
            or len(state.api_reserved_members | logical_keys) > 16384):
        return Decision(state)
    state = update(state, replace(record, api_reserved=True, api_answers=answers))
    state = replace(state, api_reserved_members=state.api_reserved_members | logical_keys)
    return Decision(state, (Intent("apiSend", record.selection.key, answers),), "reserved")


def acknowledge(state: State, key: tuple) -> Decision:
    record = state.record(key)
    if record is None or not record.api_claimed:
        return Decision(state)
    return Decision(update(state, replace(record, delivered=True)), status="delivered")


def accepted(state: State, selection: Selection, answers: tuple[Answer, ...]) -> Decision:
    record = state.record(selection.key)
    if (record is None or not record.eligible or not selection.valid()
            or len(answers) == 0 or len(answers) > len(selection.members)
            or len({a.member for a in answers}) != len(answers)
            or any(a.member not in selection.members or not valid_hash(a.value_hash) for a in answers)):
        return Decision(state)
    latest = {a.member: a for a in record.accepted_answers}
    latest.update({a.member: a for a in answers})
    ordered = tuple(latest[m] for m in selection.members if m in latest)
    record = replace(record, accepted_answers=ordered)
    return Decision(update(state, record), status="answered" if record.answered else "partiallyAnswered")


def close_guard(state: State, proof: AXProof, grant: SyntheticCASGrant | None, tick: int) -> bool:
    record = state.record(proof.selection.key)
    if record is None or grant is None:
        return False
    return (state.permission is Permission.GRANTED and record.eligible and record.answered
            and not record.renderer_closed and proof.selection.valid()
            and state.focus_key == proof.selection.key and proof.fresh and proof.exact_native_identity
            and proof.complete_drafts and proof.focused_selection and not proof.editing
            and not proof.autosend_pending and bool(proof.element) and proof.element_generation >= 0
            and proof.draft_revision == proof.accepted_baseline_revision
            and complete_answers(proof.selection, proof.drafts)
            and proof.drafts == record.accepted_answers and proof.semantics.valid()
            and grant.transactional_native_guard and grant.selection_key == proof.selection.key
            and grant.element == proof.element and grant.element_generation == proof.element_generation
            and grant.draft_revision == proof.draft_revision and grant.baseline == proof.drafts
            and bool(grant.nonce) and grant.nonce not in state.consumed_grants
            and tick <= grant.expires_tick)


def request_dismiss(state: State, proof: AXProof, grant: SyntheticCASGrant | None, tick: int) -> Decision:
    record = state.record(proof.selection.key)
    if record is None or record.dismiss_reserved or not close_guard(state, proof, grant, tick):
        return Decision(state)
    state = update(state, replace(record, dismiss_reserved=True))
    return Decision(state, (Intent("pureDismiss", proof.selection.key, ax_proof=proof, grant=grant),), "reserved")


def authorize(state: State, intent: Intent, tick: int,
              current_capability: APICapability | None = None,
              current_ax: AXProof | None = None) -> Decision:
    """Final fake-adapter guard. Status execute permits one SIMULATED log entry.

    The fake grant must also be atomically consumed by a native transactional
    adapter in any future real implementation. This ordinary reducer/read is
    not itself such a transaction and cannot close the production TOCTOU gap.
    """
    record = state.record(intent.key)
    if record is None:
        return Decision(state)
    if intent.kind == "apiSend":
        if (not record.api_reserved or record.api_claimed or record.api_unknown
                or current_capability is None or intent.answers != record.api_answers
                or not capability_matches(record, current_capability)):
            return Decision(state)
        return Decision(update(state, replace(record, api_claimed=True)), status="execute")
    if intent.kind == "pureDismiss":
        if (not record.dismiss_reserved or record.dismiss_claimed or record.dismiss_unknown
                or current_ax is None or current_ax != intent.ax_proof
                or not close_guard(state, current_ax, intent.grant, tick)):
            return Decision(state)
        grant = intent.grant
        state = update(state, replace(record, dismiss_claimed=True, dismiss_tick=tick))
        state = replace(state, consumed_grants=state.consumed_grants | {grant.nonce})
        return Decision(state, status="execute")
    return Decision(state)


def unknown(state: State, intent: Intent) -> Decision:
    record = state.record(intent.key)
    if record is None:
        return Decision(state)
    if intent.kind == "apiSend" and record.api_reserved:
        record = replace(record, api_unknown=True)
    elif intent.kind == "pureDismiss" and record.dismiss_reserved:
        record = replace(record, dismiss_unknown=True)
    else:
        return Decision(state)
    return Decision(update(state, record), status="unknown")


def verify_closed(state: State, proof: ClosedProof) -> Decision:
    record = state.record(proof.selection.key)
    if record is None:
        return Decision(state)
    other_unanswered = frozenset(r.selection.key for r in state.records
                                if r.eligible and r.selection.key != proof.selection.key
                                and not r.answered and not r.renderer_closed)
    if (not record.dismiss_claimed or not record.answered or not record.eligible
            or not proof.selection.valid() or proof.current_scope != record.selection.scope
            or state.focus_key != proof.selection.key or not proof.exact_native_identity
            or not proof.complete or not proof.navigation_unchanged or not proof.fresh
            or not proof.target_selected_group_absent or proof.observed_tick <= record.dismiss_tick
            or not other_unanswered.issubset(proof.remaining_unanswered_keys)):
        return Decision(state)
    return Decision(update(state, replace(record, renderer_closed=True)), status="rendererClosed")
