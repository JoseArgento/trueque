"""Trueque running in Lua 5.1 (the Lua of WoW) on a small stand-in for the client.

Several clients can run side by side; deliver() carries what one sent on GUILD to the others, the way the
game would. Nothing received is ever run: the tests feed broken and hostile messages too.
"""

from __future__ import annotations

from pathlib import Path

import pytest

lupa = pytest.importorskip("lupa.lua51")

ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT / "Trueque"
TESTS = Path(__file__).resolve().parent

LINEN = "|cffffffff|Hitem:2996::::::::10:::::|h[Bolt of Linen Cloth]|h|r"
WOOL = "|cffffffff|Hitem:2589::::::::10:::::|h[Linen Cloth]|h|r"
RECIPE = "|cffffd000|Henchant:3275|h[First Aid: Linen Bandage]|h|r"


def toc_lines():
    return [ln.strip() for ln in (ADDON / "Trueque.toc").read_text(encoding="utf-8").splitlines()]


def toc_files():
    return [ln.replace("\\", "/") for ln in toc_lines() if ln and not ln.startswith("#") and ln.endswith(".lua")]


class Client:
    def __init__(self, name="Josecito", locale="enUS", saved=None, setup=None):
        self.name = name
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((TESTS / "wow_mock.lua").read_text(encoding="utf-8"))
        self.lua.execute((TESTS / "trueque_mock.lua").read_text(encoding="utf-8"))
        self.m = self.lua.globals().MOCK
        self.m.player.name = name
        self.m.locale = locale
        if saved is not None:
            self.lua.execute(saved)
        if setup:
            self.lua.execute(setup)
        self.ns = self.lua.table()
        loader = self.lua.eval("function(src, name) return assert(loadstring(src, '@' .. name)) end")
        for rel in toc_files():
            loader((ADDON / rel).read_text(encoding="utf-8"), f"Trueque/{rel}")("Trueque", self.ns)

    def login(self):
        self.fire("ADDON_LOADED", "Trueque")
        self.fire("PLAYER_LOGIN")
        self.m.runTimers()  # the Q, 8 s after login
        return self

    def run(self, code):
        return self.lua.eval("function(ns, MOCK) " + code + " end")(self.ns, self.m)

    def fire(self, event, *args):
        self.m.fire(event, *args)

    def slash(self, msg):
        self.lua.globals().SlashCmdList.TRUEQUE(msg)

    def sent(self):
        s = self.m.sent
        return [(s[i].prefix, s[i].text, s[i].chatType) for i in range(1, len(s) + 1)]

    def take_sent(self):
        out = self.sent()
        self.run("MOCK.sent = {}")
        return out

    def chat(self):
        c = self.m.chat
        return [c[i] for i in range(1, len(c) + 1)]

    def whispers(self):
        w = self.m.whispers
        return [(w[i].text, w[i].target) for i in range(1, len(w) + 1)]

    def receive(self, text, sender="Ana-Forever", channel="GUILD", prefix="Trueque1"):
        self.fire("CHAT_MSG_ADDON", prefix, text, channel, sender, "", 0, 0, "", 0)

    def publish(self, kind, link, qty=None, note=""):
        return self.ns.Board.Publish(kind, link, qty, note)

    def mine(self):
        m = self.ns.Board.Mine()
        return [m[i] for i in range(1, len(m) + 1)]

    def board(self):
        b = self.ns.Board.Guild()
        return {k: v for k, v in b.items()}

    def all(self, kind="all", query=""):
        a = self.ns.Board.All(kind, query)
        return [a[i] for i in range(1, len(a) + 1)]

    def open(self):
        self.run("ns.UI.Toggle()")
        return self.run("return ns.UI.frame")

    def saved(self):
        return self.m.savedVariables("TruequeDB")


def deliver(src: Client, *dests: Client):
    """Carry what src sent on GUILD to the others."""
    for _prefix, text, chat_type in src.take_sent():
        assert chat_type == "GUILD"
        for d in dests:
            d.receive(text, sender=f"{src.name}-Forever")


@pytest.fixture
def me():
    return Client().login()


@pytest.fixture
def ana():
    return Client("Ana").login()


# posts --------------------------------------------------------------------------------------------


def test_publishing_keeps_the_item_ref_the_name_quantity_and_note(me):
    post = me.publish("want", LINEN, 4, "for shirts, I'm in Stormwind")
    assert post.kind == "want" and post.ref == "item:2996" and post.name == "Bolt of Linen Cloth"
    assert post.qty == 4 and post.note == "for shirts, I'm in Stormwind" and post.by == "Josecito-Forever"
    assert post.exp == post.at + 7 * 86400
    assert me.mine()[0].id == post.id


def test_plain_text_is_a_post_without_a_ref(me):
    post = me.publish("craft", "Linen Bandages", None, "")
    assert post.ref is None and post.name == "Linen Bandages"


def test_a_recipe_link_is_kept_as_enchant(me):
    post = me.publish("craft", RECIPE)
    assert post.ref == "enchant:3275" and post.name == "First Aid: Linen Bandage"


def test_an_empty_field_does_not_post(me):
    post, why = me.run("return ns.Board.Publish('want', '', nil, '')")
    assert post is None and why == "Shift-click an item or recipe into the field first."


def test_at_most_20_posts(me):
    for i in range(20):
        assert me.publish("have", f"Thing {i}") is not None
    post, why = me.run("return ns.Board.Publish('have', 'Thing 21', nil, '')")
    assert post is None and "20" in why


def test_closing_removes_the_post_and_tells_the_guild(me):
    post = me.publish("have", LINEN, 2)
    me.take_sent()
    assert me.ns.Board.Close(post.id).id == post.id
    assert me.mine() == []
    assert me.sent() == [("Trueque1", f"X|{post.id}", "GUILD")]


def test_posts_expire_after_the_configured_days(me):
    me.slash("dias 3")
    assert me.chat()[-1].endswith("3 days.")
    post = me.publish("want", LINEN)
    assert post.exp == post.at + 3 * 86400
    me.run("MOCK.now = MOCK.now + 3 * 86400 + 1")
    me.ns.Board.Expire()
    assert me.mine() == []


def test_days_outside_1_to_30_are_refused(me):
    me.slash("dias 99")
    assert me.run("return ns.db.settings.days") == 7
    assert me.chat()[-1] == "|cffffd100Trueque:|r /trueque days N (1 to 30)."


# sync ---------------------------------------------------------------------------------------------


def test_login_registers_the_prefix_and_asks_the_guild(me):
    assert me.run("return MOCK.prefixes['Trueque1']") is True
    assert me.sent() == [("Trueque1", "Q|1", "GUILD")]


def test_a_post_reaches_guildmates_and_they_answer_a_question(me, ana):
    me.take_sent()
    ana.take_sent()
    post = ana.publish("have", LINEN, 5, "cheap")
    deliver(ana, me)
    board = me.board()
    assert list(board) == [post.id]
    got = board[post.id]
    assert got.by == "Ana-Forever" and got.kind == "have" and got.ref == "item:2996" and got.qty == 5 and got.note == "cheap"
    assert got.name == "Bolt of Linen Cloth"
    # a newcomer asks and gets Ana's post back
    beto = Client("Beto").login()
    assert beto.sent() == [("Trueque1", "Q|1", "GUILD")]
    deliver(beto, ana, me)
    deliver(ana, beto)
    assert list(beto.board()) == [post.id]
    assert beto.board()[post.id].by == "Ana-Forever"


def test_closing_removes_it_from_guildmates(me, ana):
    post = ana.publish("want", WOOL)
    deliver(ana, me)
    assert post.id in me.board()
    ana.ns.Board.Close(post.id)
    deliver(ana, me)
    assert me.board() == {}


def test_someone_else_cannot_close_or_overwrite_your_post(me, ana):
    post = ana.publish("want", WOOL)
    deliver(ana, me)
    me.receive(f"X|{post.id}", sender="Beto-Forever")
    assert post.id in me.board()
    me.receive(f"N|{post.id}|have|item:818|Hacked|1||{post.at}|{post.exp}", sender="Beto-Forever")
    assert me.board()[post.id].by == "Ana-Forever" and me.board()[post.id].kind == "want"


def test_messages_stay_under_250_bytes_with_a_long_note(me):
    long_note = "x" * 60
    post = me.publish("have", LINEN, 1, long_note)
    text = me.ns.Sync.Encode("A", post)
    assert len(text) <= 250
    # a huge name still fits: the note goes first, then the name
    me.run(f"ns.Board.Mine()[1].name = string.rep('n', 60); ns.Board.Mine()[1].note = '{long_note}'")
    text = me.run("return ns.Sync.Encode('A', ns.Board.Mine()[1])")
    assert len(text) <= 250


def test_pipes_and_percents_in_text_travel_safely(me, ana):
    post = ana.publish("have", "100% wool | or linen", 3, "note|with|pipes 50%")
    deliver(ana, me)
    got = me.board()[post.id]
    assert got.name == "100% wool | or linen" and got.note == "note|with|pipes 50%"


def test_hostile_and_broken_messages_are_dropped(me):
    now = me.run("return MOCK.now")
    bad = [
        "A|only|two",
        f"A|id1|steal|item:1|Name|1||{now}|{now + 99}",
        f"A|id3|have|item:1|Name|1||notanumber|{now + 99}",
        f"A||have|item:1|Name|1||{now}|{now + 99}",
        f"A|id5|have|item:1|Name|1||{now}|{now - 1}",
        "Z|whatever",
        "",
    ]
    for text in bad:
        me.receive(text)
    assert me.board() == {}
    # a ref that is not a link shape is kept as plain text, never as a link
    me.receive(f"A|id6|have|item:1;DeleteCursorItem()|Name|1||{now}|{now + 99}")
    me.receive(f"A|id7|have|script:evil|Name|1||{now}|{now + 99}")
    for pid in ("id6", "id7"):
        assert me.board()[pid].ref is None and me.board()[pid].name == "Name"
        assert "|H" not in me.ns.PostLink(me.board()[pid])


def test_a_sender_is_capped_at_20_posts_on_my_board(me):
    now = me.run("return MOCK.now")
    for i in range(25):
        me.receive(f"A|p{i}|have|item:{i + 1}|Thing {i}|1||{now}|{now + 99}")
    assert len(me.board()) == 20


def test_other_channels_prefixes_and_my_own_echo_are_ignored(me):
    now = me.run("return MOCK.now")
    me.receive(f"A|x1|have|item:1|Name|1||{now}|{now + 99}", channel="PARTY")
    me.receive(f"A|x2|have|item:1|Name|1||{now}|{now + 99}", prefix="Other")
    me.receive(f"A|x3|have|item:1|Name|1||{now}|{now + 99}", sender="Josecito-Forever")
    assert me.board() == {}


def test_trial_accounts_receive_but_do_not_send_and_are_told_once():
    c = Client(setup="MOCK.trial = true").login()
    assert c.sent() == []
    assert c.chat()[-1].startswith("|cffffd100Trueque:|r Trial accounts cannot send")
    c.publish("want", LINEN)
    assert c.sent() == []
    now = c.run("return MOCK.now")
    c.receive(f"A|a1|have|item:2996|Linen|1||{now}|{now + 99}")
    assert "a1" in c.board()
    # the notice is once per account
    again = Client(saved=c.saved(), setup="MOCK.trial = true").login()
    assert not any("Trial accounts" in line for line in again.chat())


def test_without_a_guild_nothing_is_sent_and_the_board_says_so():
    c = Client(setup="MOCK.guild = nil").login()
    assert c.sent() == []
    assert c.run("return ns.UI.BoardLines().empty") == "You are not in a guild. Trueque is a guild board: join one and it fills up."
    c.publish("want", LINEN)
    assert c.sent() == []
    # with posts of mine the long text leaves the list alone: a short note under it instead
    lines = c.run("return ns.UI.BoardLines()")
    assert lines.empty is None and lines.note == "No guild: only your own posts show here."
    f = c.open()
    assert f.empty._shown is False and f.boardNote._shown is True
    # the board's note never lands in the form's note field (it did once: both were f.note)
    assert f.note._text == ""


def test_opening_the_board_asks_again_at_most_once_a_minute(me):
    me.take_sent()
    me.open()
    assert me.sent() == []  # just asked at login
    me.run("MOCK.now = MOCK.now + 61")
    me.run("ns.UI.frame:Hide(); ns.UI.Toggle()")
    assert me.sent() == [("Trueque1", "Q|1", "GUILD")]


# matches and whispers -----------------------------------------------------------------------------


def test_a_want_matches_a_have_of_the_same_item_and_is_said_once(me, ana):
    mine = me.publish("want", LINEN, 2)
    me.take_sent()
    theirs = ana.publish("have", LINEN, 10)
    deliver(ana, me)
    matches = me.run(f"return ns.Board.Matches((function() for _, p in ipairs(ns.Board.Mine()) do if p.id == '{mine.id}' then return p end end end)())")
    assert [matches[i].id for i in range(1, len(matches) + 1)] == [theirs.id]
    said = [line for line in me.chat() if "Match:" in line]
    assert said == ["|cffffd100Trueque:|r Match: Ana has it: |cffffffff|Hitem:2996|h[Bolt of Linen Cloth]|h|r."]
    deliver(ana, me)  # the same post again (an answer to a Q) does not repeat the line
    me.ns.Board.TellMatches()
    assert len([line for line in me.chat() if "Match:" in line]) == 1


def test_a_craft_matches_a_want_by_name_and_a_have_matches_a_want(me, ana):
    me.publish("want", "Linen Bandage")
    me.publish("have", WOOL, 20)
    ana.publish("craft", "linen bandage")
    ana.publish("want", WOOL)
    deliver(ana, me)
    said = [line for line in me.chat() if "Match:" in line]
    assert any("Ana can craft it" in line for line in said)
    assert any("Ana is looking for it" in line for line in said)


def test_the_buttons_whisper_the_author_only_from_a_click(me, ana):
    theirs = ana.publish("want", LINEN)
    deliver(ana, me)
    assert me.whispers() == []
    f = me.open()
    me.run(f"ns.UI.selected = ns.Board.Guild()['{theirs.id}']; ns.UI.Refresh()")
    assert f.dButton._text == "I have it"
    me.run("ns.UI.frame.dButton:GetScript('OnClick')()")
    assert me.whispers() == [("Trueque: I have what you're looking for: |cffffffff|Hitem:2996|h[Bolt of Linen Cloth]|h|r", "Ana-Forever")]
    assert me.chat()[-1] == "|cffffd100Trueque:|r Whispered Ana."
    # a "have" post gets "I'm interested"
    have = ana.publish("have", WOOL)
    deliver(ana, me)
    me.run(f"ns.UI.selected = ns.Board.Guild()['{have.id}']; ns.UI.Refresh()")
    assert f.dButton._text == "I'm interested"


def test_my_own_post_gets_edit_and_done_and_done_asks_first(me):
    post = me.publish("have", LINEN, 3, "bank")
    f = me.open()
    me.run("ns.UI.selected = ns.Board.Mine()[1]; ns.UI.Refresh()")
    assert f.dButton._text == "Done" and f.dEdit._shown is True
    assert f.dQty._text == "x3" and f.dNote.text == "bank" and f.dExp._text == "7 d"
    me.run("ns.UI.frame.dButton:GetScript('OnClick')()")
    # nothing closed yet: a popup asks
    assert me.mine() != []
    popups = me.m.popups
    assert popups[1].which == "Trueque_CLOSE" and "Bolt of Linen Cloth" in popups[1].text and popups[1].data == post.id
    me.run("StaticPopupDialogs['Trueque_CLOSE'].OnAccept(nil, MOCK.popups[1].data)")
    assert me.mine() == [] and me.whispers() == []
    assert me.sent()[-1][1] == f"X|{post.id}"
    # someone else's post has no Edit
    me.run("ns.UI.selected = nil; ns.UI.Refresh()")
    assert f.dEdit._shown is False


def test_a_post_without_quantity_means_no_limit(me):
    post = me.publish("have", LINEN, None, "")
    assert post.qty is None
    head, _sub, _tag, _match = me.run("return ns.UI.RowText(ns.Board.Mine()[1])")
    assert "x" not in head.split("]")[-1]
    f = me.open()
    me.run("ns.UI.selected = ns.Board.Mine()[1]; ns.UI.Refresh()")
    assert f.dQty._text == "no limit"
    assert f.dNoteHead._shown is False and f.dNote._shown is False
    me.run("ns.UI.frame:SelectTab('mine')")
    assert f.qtyHint._text == "Empty: no limit"
    # the quantity box accepts "" too
    me.run("ns.UI.frame.link:SetText([[" + WOOL + "]]); ns.UI.frame.qty:SetText('')")
    assert me.run("return ns.UI.PublishFromForm().qty") is None


def test_a_click_on_one_of_mine_loads_it_to_edit_and_save_keeps_id_and_date(me, ana):
    post = me.publish("want", LINEN, 2, "old note")
    me.take_sent()
    f = me.open()
    me.run("ns.UI.frame:SelectTab('mine')")
    assert f.publish._text == "Publish" and f.cancel._shown is False
    assert me.run(f"return ns.UI.Edit('{post.id}')") is True
    assert me.run("return ns.UI.editing") == post.id and me.run("return ns.UI.kind") == "want"
    assert "Bolt of Linen Cloth" in f.link._text and f.qty._text == "2" and f.note._text == "old note"
    assert f.publish._text == "Save changes" and f.cancel._shown is True and f.editing._shown is True
    me.run("ns.UI.kind = 'have'; ns.UI.frame.qty:SetText('5'); ns.UI.frame.note:SetText('new note')")
    saved = me.run("return ns.UI.PublishFromForm()")
    assert saved.id == post.id and saved.at == post.at and saved.kind == "have" and saved.qty == 5 and saved.note == "new note"
    assert saved.edited is not None and len(me.mine()) == 1
    assert me.run("return ns.UI.editing") is None and f.publish._text == "Publish" and f.cancel._shown is False
    assert f.link._text == "" and me.chat()[-1].startswith("|cffffd100Trueque:|r Updated:")
    # the guild hears it again under the same id, and replaces its copy
    assert me.sent()[-1][1].startswith(f"N|{post.id}|have|item:2996|")
    deliver(me, ana)
    theirs = ana.board()[post.id]
    assert theirs.kind == "have" and theirs.qty == 5 and theirs.note == "new note"
    # the row says it was edited
    _head, sub, _tag, _match = me.run("return ns.UI.RowText(ns.Board.Mine()[1])")
    assert sub.endswith("· edited")


def test_cancel_leaves_the_post_alone_and_clears_the_form(me):
    post = me.publish("want", LINEN, 2, "note")
    f = me.open()
    me.run(f"ns.UI.Edit('{post.id}')")
    me.run("ns.UI.frame.note:SetText('changed')")
    me.run("ns.UI.CancelEdit()")
    assert me.run("return ns.UI.editing") is None and f.link._text == "" and f.note._text == ""
    assert me.mine()[0].note == "note"


def test_closing_from_the_list_asks_and_clears_an_edit_in_progress(me):
    post = me.publish("want", LINEN)
    f = me.open()
    me.run(f"ns.UI.Edit('{post.id}')")
    me.run(f"ns.UI.AskClose(ns.Board.Get('{post.id}'))")
    assert me.m.popups[1].which == "Trueque_CLOSE"
    me.run("StaticPopupDialogs['Trueque_CLOSE'].OnAccept(nil, MOCK.popups[1].data)")
    assert me.mine() == [] and me.run("return ns.UI.editing") is None and f.cancel._shown is False


def test_hover_shows_the_game_tooltip_for_links_and_shift_click_pastes_them(me):
    me.publish("want", LINEN)
    me.publish("craft", "plain text recipe")
    f = me.open()
    linked, plain = me.run("return ns.Board.Mine()[1], ns.Board.Mine()[2]")
    assert me.run("return ns.UI.ShowLinkTip(ns.UI.frame, ns.Board.Mine()[1])") is True
    calls = [c[1] for c in me.run("return GameTooltip._calls").values()]
    assert "SetHyperlink" in calls
    assert me.run("return ns.UI.ShowLinkTip(ns.UI.frame, ns.Board.Mine()[2])") is False
    # the title on the right page has a hit frame with the same hover
    me.run("ns.UI.selected = ns.Board.Mine()[1]; ns.UI.Refresh()")
    assert f.dLinkHit is not None
    # shift-click: the link goes to the chat box; without shift, nothing
    me.run("MOCK.inserted = {}; ChatFrameUtil.InsertLink = function(t) table.insert(MOCK.inserted, t) return true end")
    assert me.run("return ns.UI.ChatLink(ns.Board.Mine()[1])") is False
    me.run("IsShiftKeyDown = function() return true end")
    assert me.run("return ns.UI.ChatLink(ns.Board.Mine()[1])") is True
    assert "Hitem:2996" in me.m.inserted[1]
    assert me.run("return ns.UI.ChatLink(ns.Board.Mine()[2])") is False


def test_the_board_and_my_posts_show_the_newest_first(me, ana):
    first = me.publish("want", LINEN)
    me.run("MOCK.now = MOCK.now + 60")
    second = me.publish("have", WOOL)
    assert [p.id for p in me.all()] == [second.id, first.id]
    ana.run("MOCK.now = MOCK.now + 120")  # each client has its own clock
    theirs = ana.publish("craft", RECIPE)
    deliver(ana, me)
    assert [p.id for p in me.all()] == [theirs.id, second.id, first.id]


# the book -----------------------------------------------------------------------------------------


def test_the_book_opens_with_two_bookmarks_and_empty_states(me):
    f = me.open()
    assert f.selected == "board" and f.tabs.board is not None and f.tabs.mine is not None
    assert f.pageR is not None  # two pages
    assert f.empty._shown is True and f.boardNote._shown is False
    assert f.empty._text.startswith("Nothing posted yet.")
    # the search box sits in its own row under the chips, full width
    pts = me.run("local p = ns.UI.frame.search._points; return p[1][2] == ns.UI.frame.filters.all, p[1][1]")
    assert pts == (True, "TOPLEFT")
    me.run("ns.UI.frame:SelectTab('mine')")
    assert f.mineEmpty._shown is True
    assert me.run("return ns.UI.frame.tabs.mine.action") is None


def test_the_form_publishes_and_clears(me):
    f = me.open()
    me.run("ns.UI.frame:SelectTab('mine')")
    me.run("ns.UI.kind = 'have'")
    me.run(f"ns.UI.frame.link:SetText([[{LINEN}]]); ns.UI.frame.qty:SetText('12'); ns.UI.frame.note:SetText('in the bank')")
    post = me.run("return ns.UI.PublishFromForm()")
    assert post.kind == "have" and post.qty == 12 and post.note == "in the bank"
    assert f.link._text == "" and f.qty._text == "" and f.note._text == ""
    assert me.chat()[-1].startswith("|cffffd100Trueque:|r Posted:")


def test_shift_click_pastes_the_link_into_the_focused_field(me):
    f = me.open()
    me.run("ns.UI.frame:SelectTab('mine')")
    me.run("ns.UI.frame.link:SetFocus()")
    me.run(f"ChatFrameUtil.InsertLink([[{WOOL}]])")
    assert f.link._text == WOOL


def test_the_board_filters_and_searches(me, ana):
    ana.publish("have", LINEN)
    ana.run("MOCK.now = MOCK.now + 60")
    ana.publish("want", WOOL, 3, "for a quest")
    deliver(ana, me)
    me.run("MOCK.now = MOCK.now + 120")
    me.publish("craft", "Bandages")
    assert [p.kind for p in me.all()] == ["craft", "want", "have"]
    assert [p.kind for p in me.all("want")] == ["want"]
    assert [p.name for p in me.all("all", "quest")] == ["Linen Cloth"]
    lines = me.run("return ns.UI.BoardLines()")
    assert lines.count == "3 posts" and lines.empty is None


def test_a_row_says_what_a_post_is(me, ana):
    theirs = ana.publish("want", LINEN, 4, "for shirts")
    deliver(ana, me)
    head, sub, tag, match = me.run(f"return ns.UI.RowText(ns.Board.Guild()['{theirs.id}'])")
    assert head == "|cff3a2313|Hitem:2996|h[Bolt of Linen Cloth]|h|r x4"
    assert sub == "for shirts · by Ana · posted 1 min ago" and tag == "want" and match is False
    me.publish("have", LINEN)
    _, _, _, match = me.run(f"return ns.UI.RowText(ns.Board.Guild()['{theirs.id}'])")
    assert match is True


def test_the_list_rows_build_without_errors(me, ana):
    ana.publish("have", LINEN, 1, "n")
    deliver(ana, me)
    me.run("""
        local row = CreateFrame("Button")
        Pergamino.TintRow(row)
        ns.UI.InitRow(row, ns.Board.All()[1])
        assert(row.head._text ~= "" and row.tag ~= nil)
    """)


# language, slash, minimap --------------------------------------------------------------------------


def test_spanish_follows_the_client_or_the_setting():
    es = Client(locale="esES").login()
    assert es.run("return ns.L.TAB_BOARD") == "Tablón"
    es.slash("idioma en")
    assert es.run("return ns.L.TAB_BOARD") == "Board"
    again = Client(locale="esES", saved=es.saved()).login()
    assert again.run("return ns.L.TAB_BOARD") == "Board"
    again.slash("idioma auto")
    assert again.run("return ns.L.TAB_BOARD") == "Tablón"
    f = again.open()
    assert f.tabs.board._text == "Tablón" and f.publish._text == "Publicar"


def test_slash_opens_mine_and_the_minimap_toggles(me):
    me.slash("mios")
    assert me.run("return ns.UI.frame.selected") == "mine"
    assert me.run("return ns.UI.minimap ~= nil and ns.UI.minimap._shown") is True
    me.slash("minimapa off")
    assert me.run("return ns.UI.minimap._shown") is False and me.run("return ns.db.settings.minimap") is False
    me.run("ns.UI.minimap:SetAngle(123); ns.UI.minimap:GetScript('OnDragStop')(ns.UI.minimap)")
    assert me.run("return ns.db.settings.minimapAngle") == 123


def test_binding_and_compartment_toggle(me):
    me.run("Trueque_Toggle()")
    assert me.run("return ns.UI.frame:IsShown()") is True
    me.run("Trueque_OnAddonCompartmentClick()")
    assert me.run("return ns.UI.frame:IsShown()") is False
    assert me.run("return BINDING_NAME_TRUEQUE_TOGGLE") == "Open / close"


def test_no_emoji_in_the_addon_strings():
    for path in ADDON.glob("*.lua"):
        text = path.read_text(encoding="utf-8")
        assert not any(ord(ch) > 0x2FFF for ch in text), path.name


# Taller ---------------------------------------------------------------------------------------------


def test_without_taller_the_button_is_hidden_and_nothing_breaks(me):
    assert me.run("return ns.Partners.HasTaller()") is False
    assert me.run("return #ns.Partners.Missing()") == 0
    f = me.open()
    me.run("ns.UI.frame:SelectTab('mine')")
    assert f.taller._shown is False


def test_tallers_shopping_list_becomes_want_posts_once():
    c = Client(setup="""
        Taller_API = { VERSION = 1, ShoppingList = function()
            return { { item = 2996, name = "Bolt of Linen Cloth", need = 10, have = 4, missing = 6 },
                     { item = 2589, name = "Linen Cloth", need = 5, have = 5, missing = 0 },
                     { item = 818, name = "Tigerseye", need = 2, have = 0, missing = 2 } }
        end }
    """).login()
    assert c.run("return ns.Partners.HasTaller()") is True
    assert c.ns.Partners.PostMissing() == 2
    posts = c.mine()
    assert [(p.kind, p.ref, p.qty) for p in posts] == [("want", "item:2996", 6), ("want", "item:818", 2)]
    assert c.chat()[-1].endswith("Posted 2 materials from Taller's shopping list.")
    assert c.ns.Partners.PostMissing() == 0  # already posted
    # a Taller that errors is harmless
    c.run("Taller_API.ShoppingList = function() error('boom') end")
    assert c.run("return #ns.Partners.Missing()") == 0


def test_saved_posts_survive_a_relog_and_the_realm_board_too(me, ana):
    me.publish("have", LINEN, 3)
    theirs = ana.publish("want", WOOL)
    deliver(ana, me)
    again = Client(saved=me.saved()).login()
    assert [p.ref for p in again.mine()] == ["item:2996"]
    assert theirs.id in again.board()


# the addon's own errors (Pergamino.Guard) -----------------------------------------------------------


def test_a_handler_error_is_kept_said_once_and_shown_to_copy(me):
    me.run("ns.Sync.OnMessage = function() error('se rompio el tablon') end")
    now = me.run("return MOCK.now")
    me.receive(f"A|e1|have|item:1|Name|1||{now}|{now + 99}")
    errs = me.run("return ns.db.errors")
    assert len(errs) == 1 and "se rompio el tablon" in errs[1].message and errs[1].label == "CHAT_MSG_ADDON"
    assert sum(1 for line in me.chat() if "had an error" in line) == 1
    me.receive(f"A|e2|have|item:1|Name|1||{now}|{now + 99}")
    assert me.run("return #ns.db.errors") == 1 and me.run("return ns.db.errors[1].count") == 2
    assert sum(1 for line in me.chat() if "had an error" in line) == 1
    me.slash("errores")
    assert me.run("return ns.UI.errorsCard:IsShown()") is True
    assert "se rompio el tablon" in me.run("return ns.UI.errorsCard.page.area.box._text")
    me.run("ns.UI.errorsCard.page.clear:GetScript('OnClick')()")
    assert me.run("return #ns.db.errors") == 0
    # the slash handler is guarded too
    me.run("ns.UI.Toggle = function() error('boom') end")
    me.slash("")
    assert me.run("return ns.db.errors[1].label") == "slash"


# links inside notes -------------------------------------------------------------------------------


def test_a_shift_clicked_item_in_the_note_travels_as_a_token_and_shows_as_a_link(me, ana):
    f = me.open()
    me.run("ns.UI.frame:SelectTab('mine')")
    me.run(f"ns.UI.frame.link:SetText([[{LINEN}]]); ns.UI.frame.note:SetText('I trade it for'); ns.UI.frame.note:SetFocus()")
    me.run(f"ChatFrameUtil.InsertLink([[{WOOL}]])")
    assert f.note._text == "I trade it for [Linen Cloth]"
    me.run("ns.UI.PublishFromForm()")
    post = me.mine()[0]
    assert post.note == "I trade it for {item:2589:Linen Cloth}"
    # on screen (rows and detail) it is a real link; the sync message carries no "|"
    assert "|Hitem:2589|h[Linen Cloth]|h" in me.run("return ns.NoteText(ns.Board.Mine()[1].note)")
    msg = me.sent()[-1][1]
    assert "{item:2589:Linen Cloth}" in msg and "|H" not in msg
    # Ana gets the same link, and a bogus token stays plain text
    ana.receive(msg, "Josecito-Forever")
    assert "|Hitem:2589|h[Linen Cloth]|h" in ana.run("return ns.NoteText(ns.Board.All()[1].note)")
    assert ana.run("return ns.NoteText('see {item:abc:Bad}')") == "see [Bad]"
    # editing shows "[Linen Cloth]" again and saving keeps the ref
    me.run(f"ns.UI.Edit('{post.id}')")
    assert f.note._text == "I trade it for [Linen Cloth]"
    me.run("ns.UI.frame.note:SetText('now [Linen Cloth] or gold')")
    me.run("ns.UI.PublishFromForm()")
    assert me.mine()[0].note == "now {item:2589:Linen Cloth} or gold"


def test_page_links_wear_ink_and_chat_links_keep_the_game_colours(me):
    post = me.publish("have", LINEN, 1, "")
    assert me.run(f"return ns.PostLink(ns.Board.Get('{post.id}'))").startswith("|cff3a2313|H")
    assert me.run(f"return ns.PostLink(ns.Board.Get('{post.id}'), 'chat')").startswith("|cffffffff|H")


def test_shift_click_with_a_field_focused_is_taken_so_the_stack_is_not_split(me):
    f = me.open()
    me.run("ns.UI.frame:SelectTab('mine')")
    me.run("ns.UI.frame.link:SetFocus()")
    # the wrapped InsertLink returns true (the game splits a stack only on false)
    assert me.run(f"return ChatFrameUtil.InsertLink([[{WOOL}]])") is True
    assert f.link._text == WOOL
    me.run("ns.UI.frame.link:ClearFocus()")
    assert me.run(f"return ChatFrameUtil.InsertLink([[{WOOL}]])") is False


def test_merging_the_minimap_buttons_hides_ours_and_the_hub_lists_it(me):
    me.open()
    entries = me.run("return Pergamino.MinimapHub.Entries()")
    assert [e.label for e in entries.values()] == ["Trueque"]
    me.slash("minimapa juntar on")
    assert me.run("return ns.db.settings.minimapMerged") is True and me.run("return Pergamino.MinimapHub.IsMerged()") is True
    assert me.run("return ns.UI.minimap._shown") is False
    assert me.run("return PergaminoMinimapHub._shown") is True
    me.slash("minimap merge off")
    assert me.run("return ns.UI.minimap._shown") is True


def test_an_error_in_the_minimap_click_or_the_compartment_is_kept(me):
    me.open()
    me.run("ns.UI.Toggle = function() error('se rompio el tablon') end")
    me.run("ns.UI.minimap:GetScript('OnClick')(ns.UI.minimap, 'LeftButton')")
    me.run("Trueque_OnAddonCompartmentClick()")
    errs = me.run("return ns.guard.Errors()")
    assert sorted(e.label for e in errs.values()) == ["compartment", "minimap"]
