"""Run only synthetic stdlib fixtures: python3 smoke.py."""
import sys
sys.dont_write_bytecode = True
from dataclasses import replace
import json
import unittest
import policy as p


def member(source="agent-a", index=0, title="Synthetic question A"):
    native_id = json.dumps(["request_user_input_async", source, index],
                           ensure_ascii=False, separators=(",", ":"))
    return p.Member(source, index, native_id, p.digest(title))


def selection(conversation="synthetic-thread-a", generation=1, members=None):
    scope = p.Scope(1001, "synthetic-incarnation-a", "synthetic-build-a", "synthetic-owner-a",
                    1, "synthetic-host-a", conversation, "synthetic-turn-a", "synthetic-entity-a")
    values = members or (member(), member("agent-b", 0, "Synthetic question B"))
    return p.Selection(scope, values[0].native_id, generation, values)


def answers(value):
    return tuple(p.Answer(m, p.digest("synthetic accepted answer " + str(i)))
                 for i, m in enumerate(value.members))


def observe(state, value):
    return p.observe(state, value).state


def prepared(value=None):
    value = value or selection()
    state = observe(p.State(), value)
    state = p.permission(state, p.Permission.GRANTED).state
    state = p.accepted(state, value, answers(value)).state
    return state, value


def ax_proof(value):
    return p.AXProof(value, "synthetic-element-a", 7, answers(value), 8, 8,
                     p.PureDismissSemantics(p.NativeBehavior.PURE_DISMISS, True, False, True, True, "Dismiss"),
                     exact_native_identity=True, complete_drafts=True, focused_selection=True,
                     editing=False, autosend_pending=False)


def grant(proof, nonce="synthetic-cas-1", expires=1000):
    return p.SyntheticCASGrant(proof.selection.key, proof.element, proof.element_generation,
                               proof.draft_revision, proof.drafts, nonce, expires,
                               transactional_native_guard=True)


def closed_proof(state, value, tick=11):
    others = frozenset(r.selection.key for r in state.records
                       if r.eligible and r.selection.key != value.key and not r.answered and not r.renderer_closed)
    return p.ClosedProof(value, value.scope, tick, True, others,
                         exact_native_identity=True, complete=True, navigation_unchanged=True, fresh=True)


class FakeAdapter:
    """A list of simulated actions. Never opens a socket, tree, TCC, or app.

    The optional after_read value models TOCTOU. This fake native CAS checks the
    exact permit against that newer value atomically before adding a log entry.
    It is a test premise, not an implementation of a real Codex lease API.
    """
    def __init__(self):
        self.actions = []

    def execute(self, state, intent, tick=10, capability=None, proof=None, after_read=None):
        decision = p.authorize(state, intent, tick, current_capability=capability, current_ax=proof)
        if decision.status != "execute":
            return decision.state
        if intent.kind == "pureDismiss" and after_read is not None and after_read != proof:
            return p.unknown(decision.state, intent).state
        self.actions.append(intent)
        return decision.state


class NativeQuestionBridgeContractSmoke(unittest.TestCase):
    def assert_handoff(self, decision):
        self.assertEqual(decision.intents, ())
        self.assertNotEqual(decision.status, "execute")
        self.assertNotEqual(decision.status, "rendererClosed")

    def reserve_close(self, state, value, proof=None):
        proof = proof or ax_proof(value)
        decision = p.request_dismiss(state, proof, grant(proof), 10)
        self.assertEqual(len(decision.intents), 1)
        return decision.state, decision.intents[0], proof

    def test_01_permission_default_disabled_never_prompts_or_closes(self):
        state, value = prepared()
        state = p.permission(state, p.Permission.DISABLED).state
        self.assert_handoff(p.request_dismiss(state, ax_proof(value), grant(ax_proof(value)), 10))
        self.assertEqual(p.State().permission, p.Permission.DISABLED)

    def test_02_permission_denied_rejects_close(self):
        state, value = prepared()
        state = p.permission(state, p.Permission.DENIED).state
        self.assert_handoff(p.request_dismiss(state, ax_proof(value), grant(ax_proof(value)), 10))

    def test_03_permission_revoked_between_reservation_and_action_rejects(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        state = p.permission(state, p.Permission.REVOKED).state
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual(adapter.actions, [])
        self.assertFalse(state.record(value.key).renderer_closed)

    def test_04_api_reservation_and_repeat_confirm_send_once(self):
        value = selection()
        state = observe(p.State(), value)
        capability = p.APICapability(value)
        first = p.confirm(state, capability, answers(value))
        self.assertEqual(len(first.intents), 1)
        self.assertTrue(first.state.record(value.key).api_reserved)
        self.assert_handoff(p.confirm(first.state, capability, answers(value)))
        adapter = FakeAdapter()
        state = adapter.execute(first.state, first.intents[0], capability=capability)
        state = adapter.execute(state, first.intents[0], capability=capability)
        self.assertEqual([i.kind for i in adapter.actions], ["apiSend"])
        self.assert_handoff(p.confirm(state, capability, answers(value)))

    def test_05_ack_is_not_accepted_or_renderer_closed(self):
        value = selection()
        state = observe(p.State(), value)
        result = p.confirm(state, p.APICapability(value), answers(value))
        state = FakeAdapter().execute(result.state, result.intents[0], capability=p.APICapability(value))
        state = p.acknowledge(state, value.key).state
        record = state.record(value.key)
        self.assertTrue(record.delivered)
        self.assertFalse(record.answered)
        self.assertFalse(record.renderer_closed)
        self.assert_handoff(p.request_dismiss(state, ax_proof(value), grant(ax_proof(value)), 10))

    def test_06_accepted_is_not_renderer_closed(self):
        state, value = prepared()
        self.assertTrue(state.record(value.key).answered)
        self.assertFalse(state.record(value.key).delivered)
        self.assertFalse(state.record(value.key).renderer_closed)
        self.assert_handoff(p.verify_closed(state, closed_proof(state, value)))

    def test_07_unknown_api_forbids_retry_route_switch_and_reobservation_reset(self):
        value = selection()
        state = observe(p.State(), value)
        first = p.confirm(state, p.APICapability(value), answers(value))
        state = p.unknown(first.state, first.intents[0]).state
        state = observe(state, value)
        self.assert_handoff(p.confirm(state, p.APICapability(value), answers(value)))
        self.assert_handoff(p.authorize(state, first.intents[0], 10, current_capability=p.APICapability(value)))
        self.assert_handoff(p.authorize(state, p.Intent("axSend", value.key), 10, current_ax=ax_proof(value)))
        self.assertTrue(state.record(value.key).api_unknown)

    def test_08_late_ack_does_not_release_unknown_send_reservation(self):
        value = selection()
        state = observe(p.State(), value)
        first = p.confirm(state, p.APICapability(value), answers(value))
        state = FakeAdapter().execute(first.state, first.intents[0], capability=p.APICapability(value))
        state = p.unknown(state, first.intents[0]).state
        state = p.acknowledge(state, value.key).state
        self.assertTrue(state.record(value.key).delivered)
        self.assertTrue(state.record(value.key).api_unknown)
        self.assert_handoff(p.confirm(state, p.APICapability(value), answers(value)))

    def test_09_every_scope_field_is_exact_for_close(self):
        state, value = prepared()
        fields = {"process": 2002, "incarnation": "other-incarnation", "build": "other-build",
                  "owner": "other-owner", "epoch": 2, "host": "other-host", "conversation": "other-thread",
                  "turn": "other-turn", "entity_key": "other-entity"}
        for field, other in fields.items():
            with self.subTest(field=field):
                wrong = replace(value, scope=replace(value.scope, **{field: other}))
                proof = ax_proof(wrong)
                self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))

    def test_10_api_capability_cannot_borrow_other_owner_epoch_or_scope(self):
        value = selection()
        state = observe(p.State(), value)
        wrong = replace(value, scope=replace(value.scope, owner="other-owner", epoch=2))
        self.assert_handoff(p.confirm(state, p.APICapability(wrong), answers(wrong)))
        for capability in [p.APICapability(value, can_submit=False), p.APICapability(value, fresh=False),
                           p.APICapability(value, resource_revoked=True)]:
            self.assert_handoff(p.confirm(state, capability, answers(value)))

    def test_11_member_source_index_native_id_content_and_order_are_exact(self):
        state, value = prepared()
        mutations = [replace(value.members[0], source="other-source"),
                     replace(value.members[0], index=9),
                     replace(value.members[0], native_id="same visible title"),
                     replace(value.members[0], question_hash=p.digest("different question"))]
        variants = [replace(value, members=(m,) + value.members[1:]) for m in mutations]
        variants += [replace(value, members=tuple(reversed(value.members))), replace(value, generation=2)]
        for wrong in variants:
            proof = ax_proof(wrong)
            self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))
        self.assert_handoff(p.accepted(state, value, (p.Answer(mutations[3], p.digest("answer")),)))

    def test_12_incomplete_duplicate_or_revoked_selection_is_not_fresh_proof(self):
        for value in [replace(selection(), complete=False), replace(selection(), fresh=False),
                      replace(selection(), resource_revoked=True), replace(selection(), owner_proven=False),
                      replace(selection(), members=(member(), member()))]:
            self.assert_handoff(p.observe(p.State(), value))

    def test_13_partial_group_answer_never_closes(self):
        value = selection()
        state = observe(p.State(), value)
        state = p.permission(state, p.Permission.GRANTED).state
        state = p.accepted(state, value, answers(value)[:1]).state
        self.assertFalse(state.record(value.key).answered)
        proof = ax_proof(value)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))

    def test_14_multiple_sources_in_one_native_selection_need_all_answers(self):
        value = selection(members=(member("source-a"), member("source-b"), member("source-c")))
        state = observe(p.State(), value)
        state = p.permission(state, p.Permission.GRANTED).state
        state = p.accepted(state, value, answers(value)[:2]).state
        proof = ax_proof(value)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))
        state = p.accepted(state, value, answers(value)[2:]).state
        self.assertEqual(len(p.request_dismiss(state, proof, grant(proof), 10).intents), 1)

    def test_15_new_later_question_invalidates_old_group_close_intent(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        appended = replace(value, generation=2, members=value.members + (member("later-source"),))
        state = observe(state, appended)
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual(adapter.actions, [])
        self.assertFalse(state.record(appended.key).answered)
        self.assertFalse(state.record(value.key).eligible)

    def test_16_new_draft_revision_even_same_text_rejects(self):
        state, value = prepared()
        proof = replace(ax_proof(value), draft_revision=9)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))

    def test_17_new_or_hidden_incomplete_draft_rejects(self):
        state, value = prepared()
        good = ax_proof(value)
        edited = replace(good.drafts[0], value_hash=p.digest("new unsent draft"))
        for proof in [replace(good, drafts=(edited,) + good.drafts[1:]),
                      replace(good, drafts=good.drafts[:1]), replace(good, complete_drafts=False),
                      replace(good, editing=True), replace(good, autosend_pending=True)]:
            self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))

    def test_18_unknown_identity_or_title_guess_is_not_scope_proof(self):
        state, value = prepared()
        proof = replace(ax_proof(value), exact_native_identity=False)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))

    def test_19_element_generation_change_before_action_rejects(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=replace(proof, element_generation=8))
        self.assertEqual(adapter.actions, [])
        self.assertFalse(state.record(value.key).dismiss_claimed)

    def test_20_permission_and_scope_resource_revoke_before_action_rejects(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        state = p.revoke(state, value.key).state
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual(adapter.actions, [])
        self.assertTrue(state.record(value.key).answered)
        self.assertFalse(state.record(value.key).renderer_closed)

    def test_21_epoch_switch_rejects_old_close_and_preserves_other_records(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        state = p.revoke(state, value.key).state
        replacement = replace(value, scope=replace(value.scope, epoch=2))
        state = observe(state, replacement)
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual(adapter.actions, [])
        self.assertFalse(state.record(replacement.key).answered)
        self.assertTrue(state.record(value.key).answered)

    def test_22_wrong_thread_navigation_after_reservation_rejects(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        state = observe(state, selection("synthetic-thread-b"))
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual(adapter.actions, [])

    def test_23_skip_attribute_reuse_never_means_pure_dismiss(self):
        state, value = prepared()
        semantics = replace(ax_proof(value).semantics, behavior=p.NativeBehavior.SKIP,
                            sends_answer=False, attribute="Dismiss")
        proof = replace(ax_proof(value), semantics=semantics)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))
        self.assert_handoff(p.authorize(state, p.Intent("skip", value.key), 10, current_ax=proof))

    def test_24_unknown_or_answer_sending_semantics_rejects(self):
        state, value = prepared()
        good = ax_proof(value)
        for semantics in [replace(good.semantics, native_contract_verified=False),
                          replace(good.semantics, sends_answer=True),
                          replace(good.semantics, preserves_other_selections=False),
                          replace(good.semantics, closes_selected_group=False),
                          replace(good.semantics, behavior=p.NativeBehavior.UNKNOWN)]:
            proof = replace(good, semantics=semantics)
            self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))

    def test_25_no_actual_transactional_lease_means_handoff(self):
        state, value = prepared()
        proof = ax_proof(value)
        self.assert_handoff(p.request_dismiss(state, proof, None, 10))
        self.assert_handoff(p.request_dismiss(state, proof,
                           replace(grant(proof), transactional_native_guard=False), 10))

    def test_26_expired_or_mismatched_grant_rejects(self):
        state, value = prepared()
        proof = ax_proof(value)
        good = grant(proof)
        for wrong in [replace(good, expires_tick=9), replace(good, element="other-element"),
                      replace(good, element_generation=99), replace(good, draft_revision=9),
                      replace(good, baseline=()), replace(good, selection_key=selection("other").key)]:
            self.assert_handoff(p.request_dismiss(state, proof, wrong, 10))

    def test_27_dismiss_reservation_and_duplicate_press_execute_once(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof, "other-grant"), 10))
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual([i.kind for i in adapter.actions], ["pureDismiss"])
        self.assertFalse(state.record(value.key).renderer_closed)

    def test_28_unknown_dismiss_result_cannot_repeat_press(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        state = p.unknown(state, intent).state
        state = observe(state, value)
        state = adapter.execute(state, intent, proof=proof)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof, "new-grant"), 20))
        self.assertEqual(len(adapter.actions), 1)
        self.assertTrue(state.record(value.key).dismiss_unknown)

    def test_29_second_read_does_not_eliminate_toctou_fake_cas_rejects_race(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        edited = replace(proof, drafts=(replace(proof.drafts[0], value_hash=p.digest("race draft")),)
                         + proof.drafts[1:], draft_revision=9)
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof, after_read=edited)
        self.assertEqual(adapter.actions, [])
        self.assertTrue(state.record(value.key).dismiss_unknown)
        self.assert_handoff(p.request_dismiss(state, proof, grant(proof, "retry"), 20))

    def test_30_fake_180ms_clock_never_selects_types_or_resubmits(self):
        value = selection()
        state = observe(p.State(), value)
        result = p.confirm(state, p.APICapability(value), answers(value))
        adapter = FakeAdapter()
        state = adapter.execute(result.state, result.intents[0], tick=0, capability=p.APICapability(value))
        for tick in [1, 179, 180, 181, 1000]:
            self.assert_handoff(p.confirm(state, p.APICapability(value), answers(value)))
            for forbidden in ["axChoose", "axType", "axConfirm", "escape", "axSend"]:
                self.assert_handoff(p.authorize(state, p.Intent(forbidden, value.key), tick, current_ax=ax_proof(value)))
        self.assertEqual([i.kind for i in adapter.actions], ["apiSend"])

    def test_31_closed_needs_new_same_scope_absence_proof(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        state = FakeAdapter().execute(state, intent, proof=proof)
        good = closed_proof(state, value)
        for wrong in [replace(good, current_scope=replace(value.scope, conversation="other")),
                      replace(good, target_selected_group_absent=False), replace(good, fresh=False),
                      replace(good, exact_native_identity=False), replace(good, complete=False),
                      replace(good, navigation_unchanged=False), replace(good, observed_tick=10)]:
            self.assert_handoff(p.verify_closed(state, wrong))
        state = p.verify_closed(state, good).state
        self.assertTrue(state.record(value.key).renderer_closed)

    def test_32_parallel_unanswered_scope_must_be_proven_retained_on_close(self):
        value = selection()
        other = selection("synthetic-thread-b")
        state = observe(p.State(), other)
        before_other = state.record(other.key)
        state = observe(state, value)
        state = p.permission(state, p.Permission.GRANTED).state
        state = p.accepted(state, value, answers(value)).state
        state, intent, proof = self.reserve_close(state, value)
        state = FakeAdapter().execute(state, intent, proof=proof)
        good = closed_proof(state, value)
        self.assert_handoff(p.verify_closed(state, replace(good, remaining_unanswered_keys=frozenset())))
        state = p.verify_closed(state, good).state
        self.assertTrue(state.record(value.key).renderer_closed)
        self.assertEqual(state.record(other.key), before_other)
        self.assertFalse(state.record(other.key).answered)

    def test_33_wrong_question_content_or_member_answer_cannot_settle(self):
        value = selection()
        state = observe(p.State(), value)
        wrong = replace(value.members[0], question_hash=p.digest("same title different native content"))
        self.assert_handoff(p.accepted(state, value, (p.Answer(wrong, p.digest("answer")),)))
        self.assertEqual(state.record(value.key).accepted_answers, ())
        self.assert_handoff(p.accepted(state, value, (answers(value)[0], answers(value)[0])))

    def test_34_new_group_with_same_visible_text_does_not_inherit_answer_or_send_state(self):
        state, value = prepared()
        later_member = member("later-source", title="Synthetic question A")
        new = replace(value, selected_item=later_member.native_id, generation=2, members=(later_member,))
        state = observe(state, new)
        self.assertFalse(state.record(new.key).answered)
        self.assertFalse(state.record(new.key).api_reserved)
        self.assertFalse(state.record(new.key).dismiss_reserved)
        result = p.confirm(state, p.APICapability(new), answers(new))
        self.assertEqual(len(result.intents), 1)
        self.assertEqual(result.intents[0].key, new.key)

    def test_35_final_guard_rechecks_api_capability_before_fake_dispatch(self):
        value = selection()
        state = observe(p.State(), value)
        result = p.confirm(state, p.APICapability(value), answers(value))
        adapter = FakeAdapter()
        state = adapter.execute(result.state, result.intents[0], capability=p.APICapability(value, resource_revoked=True))
        self.assertEqual(adapter.actions, [])
        self.assertTrue(state.record(value.key).api_reserved)

    def test_36_incomplete_answers_never_reserve_api_send(self):
        value = selection()
        state = observe(p.State(), value)
        for values in [(), answers(value)[:1], tuple(reversed(answers(value))),
                       (replace(answers(value)[0], value_hash=""),) + answers(value)[1:]]:
            self.assert_handoff(p.confirm(state, p.APICapability(value), values))
            self.assertFalse(state.record(value.key).api_reserved)


    def test_37_unknown_member_send_reservation_survives_selection_generation(self):
        value = selection()
        state = observe(p.State(), value)
        first = p.confirm(state, p.APICapability(value), answers(value))
        state = p.unknown(first.state, first.intents[0]).state
        later = replace(value, generation=2, members=value.members + (member("later-source"),))
        state = observe(state, later)
        self.assert_handoff(p.confirm(state, p.APICapability(later), answers(later)))
        self.assertEqual(len(state.api_reserved_members), len(value.members))

    def test_38_unknown_member_send_reservation_survives_owner_epoch_reconnect(self):
        value = selection()
        state = observe(p.State(), value)
        first = p.confirm(state, p.APICapability(value), answers(value))
        state = p.unknown(first.state, first.intents[0]).state
        replacement = replace(value, scope=replace(value.scope, owner="replacement-owner", epoch=2))
        state = observe(state, replacement)
        self.assert_handoff(p.confirm(state, p.APICapability(replacement), answers(replacement)))
        self.assertTrue(state.record(value.key).api_unknown)

    def test_39_answered_members_are_carried_when_later_question_appends(self):
        state, value = prepared()
        later = replace(value, generation=2, members=value.members + (member("later-source"),))
        state = observe(state, later)
        self.assertEqual(state.record(later.key).accepted_answers, answers(value))
        self.assert_handoff(p.confirm(state, p.APICapability(later), answers(later)))
        last_only = (answers(later)[-1],)
        decision = p.confirm(state, p.APICapability(later), last_only)
        self.assertEqual(len(decision.intents), 1)
        self.assertEqual(decision.intents[0].answers, last_only)
        self.assertFalse(decision.state.record(later.key).answered)


    def test_40_host_changes_block_old_dismiss_and_preserve_host_scoped_unknown_send(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        other_host = replace(value, scope=replace(value.scope, host="synthetic-host-b"))
        state = observe(state, other_host)
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual(adapter.actions, [])
        self.assertFalse(state.record(value.key).renderer_closed)
        state = observe(p.State(), value)
        first = p.confirm(state, p.APICapability(value), answers(value))
        state = p.unknown(first.state, first.intents[0]).state
        state = observe(state, other_host)
        # A proven different host is an independent namespace, never borrowed
        # capability or reset of the old host's unknown member reservation.
        other = p.confirm(state, p.APICapability(other_host), answers(other_host))
        self.assertEqual(len(other.intents), 1)
        state = observe(other.state, value)
        self.assert_handoff(p.confirm(state, p.APICapability(value), answers(value)))
        self.assertTrue(state.record(value.key).api_unknown)
        self.assertTrue(all(key[0] in ("synthetic-host-a", "synthetic-host-b")
                            for key in state.api_reserved_members))

    def test_41_selected_native_item_change_without_membership_change_invalidates_old_dismiss(self):
        state, value = prepared()
        state, intent, proof = self.reserve_close(state, value)
        changed = replace(value, selected_item=value.members[1].native_id)
        self.assertEqual(changed.members, value.members)
        self.assertEqual(changed.generation, value.generation)
        self.assertNotEqual(changed.key, value.key)
        state = observe(state, changed)
        adapter = FakeAdapter()
        state = adapter.execute(state, intent, proof=proof)
        self.assertEqual(adapter.actions, [])
        self.assertFalse(state.record(value.key).renderer_closed)
        self.assert_handoff(p.verify_closed(state, closed_proof(state, changed)))
        state = observe(p.State(), value)
        first = p.confirm(state, p.APICapability(value), answers(value))
        state = p.unknown(first.state, first.intents[0]).state
        state = observe(state, changed)
        self.assert_handoff(p.confirm(state, p.APICapability(changed), answers(changed)))
        self.assertTrue(state.record(value.key).api_unknown)
        self.assertEqual(len(state.api_reserved_members), len(value.members))

    def test_42_missing_or_non_string_host_and_selected_item_are_unproven(self):
        value = selection()
        for wrong in [replace(value, scope=replace(value.scope, host="")),
                      replace(value, scope=replace(value.scope, host=True)),
                      replace(value, selected_item=""), replace(value, selected_item=True)]:
            self.assert_handoff(p.observe(p.State(), wrong))
            state, _ = prepared()
            proof = ax_proof(wrong)
            self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))


    def test_43_nonmember_noncanonical_and_malformed_member_identity_reject(self):
        value = selection()
        selected_nonmember = member("not-a-selected-member").native_id
        selected_noncanonical = json.dumps(["request_user_input_async", value.members[0].source, 0])
        wrong_selections = [replace(value, selected_item=selected_nonmember),
                            replace(value, selected_item=selected_noncanonical)]
        for source in [None, True, False, 0, 123, [], {}, ""]:
            malformed = replace(value.members[0], source=source)
            self.assertFalse(malformed.valid())
            wrong_selections.append(replace(value, members=(malformed,) + value.members[1:]))
        for question_hash in [None, True, 1, [], {}, "", "z" * 64]:
            self.assertFalse(p.valid_hash(question_hash))
            malformed = replace(value.members[0], question_hash=question_hash)
            wrong_selections.append(replace(value, members=(malformed,) + value.members[1:]))
        for wrong in wrong_selections:
            with self.subTest(selected=wrong.selected_item, member=wrong.members[0]):
                self.assertFalse(wrong.valid())
                self.assert_handoff(p.observe(p.State(), wrong))
                state, _ = prepared()
                proof = ax_proof(wrong)
                self.assert_handoff(p.request_dismiss(state, proof, grant(proof), 10))

    def test_44_new_known_thread_authority_rejects_old_unclaimed_send_preserves_parallel(self):
        changes = {"owner": "new-owner", "epoch": 2, "process": 2002,
                   "incarnation": "new-incarnation", "build": "new-build", "turn": "new-turn"}
        for field, changed in changes.items():
            with self.subTest(field=field):
                value = selection()
                parallel_thread = selection("synthetic-thread-b")
                parallel_host = replace(selection(), scope=replace(selection().scope, host="synthetic-host-b"))
                state = observe(observe(observe(p.State(), parallel_thread), parallel_host), value)
                before_parallel = (state.record(parallel_thread.key), state.record(parallel_host.key))
                result = p.confirm(state, p.APICapability(value), answers(value))
                self.assertFalse(result.state.record(value.key).api_claimed)
                reservation = result.state.api_reserved_members
                newer = replace(value, scope=replace(value.scope, **{field: changed}))
                state = observe(result.state, newer)
                self.assertFalse(state.record(value.key).eligible)
                adapter = FakeAdapter()
                state = adapter.execute(state, result.intents[0], capability=p.APICapability(value, fresh=True))
                self.assertEqual(adapter.actions, [])
                self.assertFalse(state.record(value.key).api_claimed)
                self.assertEqual(state.api_reserved_members, reservation)
                self.assertEqual((state.record(parallel_thread.key), state.record(parallel_host.key)), before_parallel)
                # Reobservation cannot erase the old reservation or create a new send intent.
                state = observe(state, value)
                self.assert_handoff(p.confirm(state, p.APICapability(value), answers(value)))
                self.assertEqual(state.api_reserved_members, reservation)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(NativeQuestionBridgeContractSmoke)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print(f"NATIVE_QUESTION_BRIDGE_CONTRACT_CASES={result.testsRun}")
    print(f"NATIVE_QUESTION_BRIDGE_CONTRACT_FAILURES={len(result.failures) + len(result.errors)}")
    print("NATIVE_QUESTION_BRIDGE_CONTRACT_REAL_ACTIONS=0")
    sys.exit(0 if result.wasSuccessful() else 1)
