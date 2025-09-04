LOVELY_INTEGRITY = '1b3ba980206ff2d94c8c36fe22a52d0b4d62e673afa2f781886d6bbafc56c143'

--class
Card = Moveable:extend()

--class methods
function Card:init(X, Y, W, H, card, center, params)
    self.params = (type(params) == 'table') and params or {}

    Moveable.init(self,X, Y, W, H)

    self.CT = self.VT
    self.config = {
        card = card or {},
        center = center
        }
    self.tilt_var = {mx = 0, my = 0, dx = 0, dy = 0, amt = 0}
    self.ambient_tilt = 0.2

    self.states.collide.can = true
    self.states.hover.can = true
    self.states.drag.can = true
    self.states.click.can = true

    self.playing_card = self.params.playing_card
    G.sort_id = (G.sort_id or 0) + 1
    self.sort_id = G.sort_id

    if self.params.viewed_back then self.back = 'viewed_back'
    else self.back = 'selected_back' end
    self.bypass_discovery_center = self.params.bypass_discovery_center
    self.bypass_discovery_ui = self.params.bypass_discovery_ui
    self.bypass_lock = self.params.bypass_lock
    self.no_ui = self.config.card and self.config.card.no_ui
    self.children = {}
    self.base_cost = 0
    self.extra_cost = 0
    self.cost = 0
    self.sell_cost = 0
    self.sell_cost_label = 0
    self.children.shadow = Moveable(0, 0, 0, 0)
    self.unique_val = 1-self.ID/1603301
    self.edition = nil
    self.zoom = true
    self:set_ability(center, true)
    self:set_base(card, true)

    self.discard_pos = {
        r = 0,
        x = 0,
        y = 0,
    }
 
    self.facing = 'front'
    self.sprite_facing = 'front'
    self.flipping = nil
    self.area = nil
    self.highlighted = false
    self.click_timeout = 0.3
    self.T.scale = 0.95
    self.debuff = false

    self.rank = nil
    self.added_to_deck = nil

    if self.children.front then self.children.front.VT.w = 0 end
    self.children.back.VT.w = 0
    self.children.center.VT.w = 0

    if self.children.front then self.children.front.parent = self; self.children.front.layered_parallax = nil end
    self.children.back.parent = self; self.children.back.layered_parallax = nil
    self.children.center.parent = self; self.children.center.layered_parallax = nil

    self:set_cost()

    if getmetatable(self) == Card then 
        table.insert(G.I.CARD, self)
    end
end

function Card:update_alert()
    if self.ability.set == 'Default' and self.config.center and self.config.center.key == 'c_base' and self.seal then
        if G.P_SEALS[self.seal].alerted and self.children.alert then
            self.children.alert:remove()
            self.children.alert = nil
        elseif not G.P_SEALS[self.seal].alerted and not self.children.alert and G.P_SEALS[self.seal].discovered then
            self.children.alert = UIBox{
                definition = create_UIBox_card_alert(), 
                config = {align="tli",
                        offset = {x = 0.1, y = 0.1},
                        parent = self}
            }
        end
    end
    if (self.ability.set == 'Joker' or self.ability.set == 'Voucher' or self.ability.consumeable or self.ability.set == 'Edition' or self.ability.set == 'Booster') then 
        if self.area and self.area.config.collection and self.config.center then
            if self.config.center.alerted and self.children.alert  then
                self.children.alert:remove()
                self.children.alert = nil
            elseif not self.config.center.alerted and not self.children.alert and self.config.center.discovered then
                self.children.alert = UIBox{
                    definition = create_UIBox_card_alert(), 
                    config = {align=(self.ability.set == 'Voucher' and (self.config.center.order%2)==1) and "tli" or "tri",
                            offset = {x = (self.ability.set == 'Voucher' and (self.config.center.order%2)==1) and 0.1 or -0.1, y = 0.1},
                            parent = self}
                }
            end
        end
    end
end

function Card:set_base(card, initial)
SMODS.enh_cache:write(self, nil)
    card = card or {}

    self.config.card = card
    for k, v in pairs(G.P_CARDS) do
        if card == v then self.config.card_key = k end
    end
    
    if next(card) then
        self:set_sprites(nil, card)
    end

    local suit_base_nominal_original = nil
    if self.base and self.base.suit_nominal_original then suit_base_nominal_original = self.base.suit_nominal_original end
    self.base = {
        name = self.config.card.name,
        suit = self.config.card.suit,
        value = self.config.card.value,
        nominal = 0,
        suit_nominal = 0,
        face_nominal = 0,
        colour = G.C.SUITS[self.config.card.suit],
        times_played = 0
    }

    local rank = SMODS.Ranks[self.base.value] or {}
    self.base.nominal = rank.nominal or 0
    self.base.face_nominal = rank.face_nominal or 0
    self.base.id = rank.id

    if initial then self.base.original_value = self.base.value end

    local suit = SMODS.Suits[self.base.suit] or {}
    self.base.suit_nominal = suit.suit_nominal or 0
    self.base.suit_nominal_original = suit_base_nominal_original or suit.suit_nominal or 0

    if not initial and G.GAME and G.GAME.blind then G.GAME.blind:debuff_card(self) end
    if self.playing_card and not initial then check_for_unlock({type = 'modify_deck'}) end
end

function Card:set_sprites(_center, _front)
    if _front then 
        local _atlas, _pos = get_front_spriteinfo(_front)
        if self.children.front then
            self.children.front.atlas = _atlas
            self.children.front:set_sprite_pos(_pos)
        else
            self.children.front = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, _atlas, _pos)
            self.children.front.states.hover = self.states.hover
            self.children.front.states.click = self.states.click
            self.children.front.states.drag = self.states.drag
            self.children.front.states.collide.can = false
            self.children.front:set_role({major = self, role_type = 'Glued', draw_major = self})
        end
    end
    if _center then 
        if _center.set then
            if self.children.center then
                self.children.center.atlas = G.ASSET_ATLAS[(_center.atlas or (_center.set == 'Joker' or _center.consumeable or _center.set == 'Voucher') and _center.set) or 'centers']
                self.children.center:set_sprite_pos(_center.pos)
            else
                if _center.set == 'Joker' and not _center.unlocked and not self.params.bypass_discovery_center then 
                    self.children.center = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS["Joker"], G.j_locked.pos)
                elseif self.config.center.set == 'Voucher' and not self.config.center.unlocked and not self.params.bypass_discovery_center then 
                    self.children.center = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS["Voucher"], G.v_locked.pos)
                elseif self.config.center.consumeable and self.config.center.demo then 
                    self.children.center = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS["Tarot"], G.c_locked.pos)
                elseif not self.params.bypass_discovery_center and (_center.set == 'Edition' or _center.set == 'Joker' or _center.consumeable or _center.set == 'Voucher' or _center.set == 'Booster') and not _center.discovered then 
                    self.children.center = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS[_center.atlas or _center.set], 
                    (_center.set == 'Joker' and G.j_undiscovered.pos) or 
                    (_center.set == 'Edition' and G.j_undiscovered.pos) or 
                    (_center.set == 'Tarot' and G.t_undiscovered.pos) or 
                    (_center.set == 'Planet' and G.p_undiscovered.pos) or 
                    (_center.set == 'Spectral' and G.s_undiscovered.pos) or 
                    (_center.set == 'Voucher' and G.v_undiscovered.pos) or 
                    (_center.set == 'Booster' and G.booster_undiscovered.pos))
                elseif _center.set == 'Joker' or _center.consumeable or _center.set == 'Voucher' then
                    self.children.center = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS[_center.set], self.config.center.pos)
                else
                    self.children.center = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS[_center.atlas or 'centers'], _center.pos)
                end
                self.children.center.states.hover = self.states.hover
                self.children.center.states.click = self.states.click
                self.children.center.states.drag = self.states.drag
                self.children.center.states.collide.can = false
                self.children.center:set_role({major = self, role_type = 'Glued', draw_major = self})
            end
            if _center.name == 'Half Joker' and (_center.discovered or self.bypass_discovery_center) then 
                self.children.center.scale.y = self.children.center.scale.y/1.7
            end
            if _center.name == 'Photograph' and (_center.discovered or self.bypass_discovery_center) then 
                self.children.center.scale.y = self.children.center.scale.y/1.2
            end
            if _center.name == 'Square Joker' and (_center.discovered or self.bypass_discovery_center) then 
                self.children.center.scale.y = self.children.center.scale.x
            end
            if _center.pixel_size and _center.pixel_size.h and (_center.discovered or self.bypass_discovery_center) then
                self.children.center.scale.y = self.children.center.scale.y*(_center.pixel_size.h/95)
            end
            if _center.pixel_size and _center.pixel_size.w and (_center.discovered or self.bypass_discovery_center) then
                self.children.center.scale.x = self.children.center.scale.x*(_center.pixel_size.w/71)
            end
        end

        if _center.soul_pos then 
            self.children.floating_sprite = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS['Joker'], self.config.center.soul_pos)
            self.children.floating_sprite.role.draw_major = self
            self.children.floating_sprite.states.hover.can = false
            self.children.floating_sprite.states.click.can = false
        end

        if not self.children.back then
            self.children.back = Sprite(self.T.x, self.T.y, self.T.w, self.T.h, G.ASSET_ATLAS["centers"], self.params.bypass_back or (self.playing_card and G.GAME[self.back].pos or G.P_CENTERS['b_red'].pos))
            self.children.back.states.hover = self.states.hover
            self.children.back.states.click = self.states.click
            self.children.back.states.drag = self.states.drag
            self.children.back.states.collide.can = false
            self.children.back:set_role({major = self, role_type = 'Glued', draw_major = self})
        end
    end
end

function Card:set_ability(center, initial, delay_sprites)
SMODS.enh_cache:write(self, nil)
    local X, Y, W, H = self.T.x, self.T.y, self.T.w, self.T.h

    local old_center = self.config.center
    if old_center and not next(SMODS.find_card(old_center.key, true)) then
        G.GAME.used_jokers[old_center.key] = nil
    end
    if self.added_to_deck and old_center and not self.debuff then
        self:remove_from_deck()
        self.added_to_deck = true
    end
    if type(center) == 'string' then
        assert(G.P_CENTERS[center])
        center = G.P_CENTERS[center]
    end
    self.config.center = center
    self.sticker_run = nil
    for k, v in pairs(G.P_CENTERS) do
        if center == v then self.config.center_key = k end
    end

    if self.params.discover and not center.discovered then
        unlock_card(center)
        discover_card(center)
    end

    if center.name == "Half Joker" and (center.discovered or self.bypass_discovery_center) then 
        H = H/1.7
        self.T.h = H
    end

    if center.name == "Photograph" and (center.discovered or self.bypass_discovery_center) then 
        H = H/1.2
        self.T.h = H
    end

    if center.name == "Square Joker" and (center.discovered or self.bypass_discovery_center) then 
        H = W
        self.T.h = H
    end

    if center.name == "Wee Joker" and (center.discovered or self.bypass_discovery_center) then 
        H = H*0.7
        W = W*0.7
        self.T.h = H
        self.T.w = W
    end
    if center.display_size and center.display_size.h and (center.discovered or self.bypass_discovery_center) then
        H = H*(center.display_size.h/95)
        self.T.h = H
    elseif center.pixel_size and center.pixel_size.h and (center.discovered or self.bypass_discovery_center) then
        H = H*(center.pixel_size.h/95)
        self.T.h = H
    end
    if center.display_size and center.display_size.w and (center.discovered or self.bypass_discovery_center) then
        W = W*(center.display_size.w/71)
        self.T.w = W
    elseif center.pixel_size and center.pixel_size.w and (center.discovered or self.bypass_discovery_center) then
        W = W*(center.pixel_size.w/71)
        self.T.w = W
    end

    if delay_sprites == 'quantum' then
    elseif delay_sprites then 
        self.ability.delayed = true
        G.E_MANAGER:add_event(Event({
            func = function()
                if not self.REMOVED then
                    self:set_sprites(center)
                    self.ability.delayed = false
                end
                return true
            end
        })) 
    else
        self:set_sprites(center)
    end

    if self.ability and old_center and old_center.config.bonus then
        self.ability.bonus = self.ability.bonus - old_center.config.bonus
    end
    
    local new_ability = {
        name = center.name,
        effect = center.effect,
        set = center.set,
        mult = center.config.mult or 0,
        h_mult = center.config.h_mult or 0,
        h_x_mult = center.config.h_x_mult or 0,
        h_dollars = center.config.h_dollars or 0,
        p_dollars = center.config.p_dollars or 0,
        t_mult = center.config.t_mult or 0,
        t_chips = center.config.t_chips or 0,
        x_mult = center.config.Xmult or center.config.x_mult or 1,
        h_chips = center.config.h_chips or 0,
        x_chips = center.config.x_chips or 1,
        h_x_chips = center.config.h_x_chips or 1,
        h_size = center.config.h_size or 0,
        d_size = center.config.d_size or 0,
        extra = copy_table(center.config.extra) or nil,
        extra_value = 0,
        type = center.config.type or '',
        order = center.order or nil,
        forced_selection = self.ability and self.ability.forced_selection or nil,
        perma_bonus = self.ability and self.ability.perma_bonus or 0,
        eternal = self.ability and self.ability.eternal,
        perishable = self.ability and self.ability.perishable,
        perish_tally = self.ability and self.ability.perish_tally,
        rental = self.ability and self.ability.rental,
        perma_x_chips = self.ability and self.ability.perma_x_chips or 0,
        perma_mult = self.ability and self.ability.perma_mult or 0,
        perma_x_mult = self.ability and self.ability.perma_x_mult or 0,
        perma_h_chips = self.ability and self.ability.perma_h_chips or 0,
        perma_h_x_chips = self.ability and self.ability.perma_h_x_chips or 0,
        perma_h_mult = self.ability and self.ability.perma_hmult or 0,
        perma_h_x_mult = self.ability and self.ability.perma_h_x_mult or 0,
        perma_p_dollars = self.ability and self.ability.perma_p_dollars or 0,
        perma_h_dollars = self.ability and self.ability.perma_h_dollars or 0,
    }
    self.ability = self.ability or {}
    new_ability.extra_value = nil
    self.ability.extra_value = self.ability.extra_value or 0
    for k, v in pairs(new_ability) do
        self.ability[k] = v
    end
    -- reset keys do not persist an ability change
    local reset_keys = {'name', 'effect', 'set', 'extra', 'played_this_ante', 'perma_debuff'}
    for _, mod in ipairs(SMODS.mod_list) do
        if mod.set_ability_reset_keys then
            local keys = mod.set_ability_reset_keys()
            for _, v in pairs(keys) do table.insert(reset_keys, v) end
        end
    end
    for _, k in ipairs(reset_keys) do
        self.ability[k] = new_ability[k]
    end

    self.ability.bonus = (self.ability.bonus or 0) + (center.config.bonus or 0)
    if not self.ability.name then self.ability.name = center.key end
    for k, v in pairs(center.config) do
        if k ~= 'bonus' then
            if type(v) == 'table' then
                self.ability[k] = copy_table(v)
            else
                self.ability[k] = v
            end
        end
    end

    if center.consumeable then 
        self.ability.consumeable = center.config
    end

    if self.ability.name == 'Gold Card' and self.seal == 'Gold' and self.playing_card then 
        check_for_unlock({type = 'double_gold'})
    end
    if self.ability.name == "Invisible Joker" then 
        self.ability.invis_rounds = 0
    end
    if self.ability.name == 'To Do List' then
        local _poker_hands = {}
        for k, v in pairs(G.GAME.hands) do
            if v.visible then _poker_hands[#_poker_hands+1] = k end
        end
        local old_hand = self.ability.to_do_poker_hand
        self.ability.to_do_poker_hand = nil

        while not self.ability.to_do_poker_hand do
            self.ability.to_do_poker_hand = pseudorandom_element(_poker_hands, pseudoseed((self.area and self.area.config.type == 'title') and 'false_to_do' or 'to_do'))
            if self.ability.to_do_poker_hand == old_hand then self.ability.to_do_poker_hand = nil end
        end
    end
    if self.ability.name == 'Caino' then 
        self.ability.caino_xmult = 1
    end
    if self.ability.name == 'Yorick' then 
        self.ability.yorick_discards = self.ability.extra.discards
    end
    if self.ability.name == 'Loyalty Card' then 
        self.ability.burnt_hand = 0
        self.ability.loyalty_remaining = self.ability.extra.every
    end

    self.ability.cry_prob = 1
    self.base_cost = center.cost or 1

    self.ability.hands_played_at_create = G.GAME and G.GAME.hands_played or 0

    self.label = center.label or self.config.card and self.config.card.label or self.ability.set
    if self.ability.set == 'Joker' then self.label = self.ability.name end
    if self.ability.set == 'Edition' then self.label = self.ability.name end
    if self.ability.consumeable then self.label = self.ability.name end
    if self.ability.set == 'Voucher' then self.label = self.ability.name end
    if self.ability.set == 'Booster' then
        self.label = self.ability.name
        self.mouse_damping = 1.5
    end

    local obj = self.config.center
    if obj.set_ability and type(obj.set_ability) == 'function' then
        obj:set_ability(self, initial, delay_sprites)
    end
    
    if not G.OVERLAY_MENU then 
        if self.config.center.key then
            G.GAME.used_jokers[self.config.center.key] = true
        end

    end

    if G.jokers and self.area == G.jokers then 
        check_for_unlock({type = 'modify_jokers'})
    end

    if self.added_to_deck and old_center and not self.debuff then
        self.added_to_deck = false
        self:add_to_deck()
    end
    if G.consumeables and self.area == G.consumeables then 
        check_for_unlock({type = 'modify_jokers'})
    end

    if not initial and G.GAME and G.GAME.blind then G.GAME.blind:debuff_card(self) end
    if self.playing_card and not initial then check_for_unlock({type = 'modify_deck'}) end
end

function Card:set_cost()
    self.extra_cost = 0 + G.GAME.inflation
    if self.edition then
        for k, v in pairs(G.P_CENTER_POOLS.Edition) do
            if self.edition[v.key:sub(3)] then
                if v.extra_cost then
                    self.extra_cost = self.extra_cost + v.extra_cost
                end
            end
        end
    end
    self.cost = math.max(1, math.floor((self.base_cost + self.extra_cost + 0.5)*(100-G.GAME.discount_percent)/100))
        if self.ability.set == 'Joker' then
            self.cost = cry_format(self.cost * G.GAME.cry_shop_joker_price_modifier,'%.2f') end
        if self.misprint_cost_fac then
            self.cost = cry_format(self.cost * self.misprint_cost_fac,'%.2f')
        if not G.GAME.modifiers.cry_misprint_min then self.cost = math.floor(self.cost) end end
    if self.ability.set == 'Booster' and G.GAME.modifiers.booster_ante_scaling then self.cost = self.cost + G.GAME.round_resets.ante - 1 end
    if self.ability.set == 'Booster' and (not G.SETTINGS.tutorial_complete) and G.SETTINGS.tutorial_progress and (not G.SETTINGS.tutorial_progress.completed_parts['shop_1']) then
        self.cost = self.cost + 3
    end
    if (self.ability.set == 'Planet' or (self.ability.set == 'Booster' and self.ability.name:find('Celestial'))) and #find_joker('Astronomer') > 0 then self.cost = 0 end
    if self.ability.rental and (not (self.ability.set == "Planet" and #find_joker('Astronomer') > 0) and self.ability.set ~= "Booster") then self.cost = 1 end
    self.sell_cost = math.max(1, math.floor(self.cost/2)) + (self.ability.extra_value or 0)
    if self.area and self.ability.couponed and (self.area == G.shop_jokers or self.area == G.shop_booster) then self.cost = 0 end
    self.sell_cost_label = (self.facing == 'back' and '?') or (G.GAME.modifiers.cry_no_sell_value and 0) or self.sell_cost
end

function Card:set_edition(edition, immediate, silent)
    self.edition = nil
    if not edition then return end
    if edition.holo then
        if not self.edition then self.edition = {} end
        self.edition.mult = G.P_CENTERS.e_holo.config.extra
        self.edition.holo = true
        self.edition.type = 'holo'
    elseif edition.foil then
        if not self.edition then self.edition = {} end
        self.edition.chips = G.P_CENTERS.e_foil.config.extra
        self.edition.foil = true
        self.edition.type = 'foil'
    elseif edition.polychrome then
        if not self.edition then self.edition = {} end
        self.edition.x_mult = G.P_CENTERS.e_polychrome.config.extra
        self.edition.polychrome = true
        self.edition.type = 'polychrome'
    elseif edition.negative then
        if not self.edition then
            self.edition = {}
            if self.added_to_deck then --Need to override if adding negative to an existing joker
                if self.ability.consumeable then
                    G.consumeables.config.card_limit = G.consumeables.config.card_limit + 1
                else
                    G.jokers.config.card_limit = G.jokers.config.card_limit + 1
                end
            end
        end
        self.edition.negative = true
        self.edition.type = 'negative'
    end

    if self.area and self.area == G.jokers then 
        if self.edition then
            if self.edition.type and G.P_CENTERS['e_'..(self.edition.type)] and not G.P_CENTERS['e_'..(self.edition.type)].discovered then
                discover_card(G.P_CENTERS['e_'..(self.edition.type)])
            end
        else
            if not G.P_CENTERS['e_base'].discovered then 
                discover_card(G.P_CENTERS['e_base'])
            end
        end
    end

    if self.edition and (not Talisman.config_file.disable_anims or (not Talisman.calculating_joker and not Talisman.calculating_score and not Talisman.calculating_card)) and not silent then
        G.CONTROLLER.locks.edition = true
        G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = not immediate and 0.2 or 0,
            blockable = not immediate,
            func = function()
                self:juice_up(1, 0.5)
                if self.edition.foil then play_sound('foil1', 1.2, 0.4) end
                if self.edition.holo then play_sound('holo1', 1.2*1.58, 0.4) end
                if self.edition.polychrome then play_sound('polychrome1', 1.2, 0.7) end
                if self.edition.negative then play_sound('negative', 1.5, 0.4) end
               return true
            end
          }))
          G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0.1,
            func = function()
                G.CONTROLLER.locks.edition = false
               return true
            end
          }))
    end

    if G.jokers and self.area == G.jokers then 
        check_for_unlock({type = 'modify_jokers'})
    end

    self:set_cost()
end

function Card:set_seal(_seal, silent, immediate)
SMODS.enh_cache:write(self, nil)
    self.seal = nil
    if _seal then
        self.seal = _seal
        self.ability.seal = {}
        for k, v in pairs(G.P_SEALS[_seal].config or {}) do
            if type(v) == 'table' then
                self.ability.seal[k] = copy_table(v)
            else
                self.ability.seal[k] = v
            end
        end
        if not silent then 
        G.CONTROLLER.locks.seal = true
        local sound = G.P_SEALS[_seal].sound or {sound = 'gold_seal', per = 1.2, vol = 0.4}
            if immediate then 
                self:juice_up(0.3, 0.3)
                play_sound(sound.sound, sound.per, sound.vol)
                G.CONTROLLER.locks.seal = false
            else
                G.E_MANAGER:add_event(Event({
                    trigger = 'after',
                    delay = 0.3,
                    func = function()
                        self:juice_up(0.3, 0.3)
                        play_sound(sound.sound, sound.per, sound.vol)
                    return true
                    end
                }))
                G.E_MANAGER:add_event(Event({
                    trigger = 'after',
                    delay = 0.15,
                    func = function()
                        G.CONTROLLER.locks.seal = false
                    return true
                    end
                }))
            end
        end
    end
    if self.ability.name == 'Gold Card' and self.seal == 'Gold' and self.playing_card then 
        check_for_unlock({type = 'double_gold'})
    end
    self:set_cost()
end

function Card:get_seal(bypass_debuff)
    if self.debuff and not bypass_debuff then return end
    return self.seal
end

function Card:set_eternal(_eternal)
    self.ability.eternal = nil
    if self.config.center.eternal_compat and not self.ability.perishable then
        self.ability.eternal = _eternal
    end
end

function Card:set_perishable(_perishable) 
    self.ability.perishable = nil
    if self.config.center.perishable_compat and not self.ability.eternal then 
        self.ability.perishable = true
        self.ability.perish_tally = G.GAME.perishable_rounds
    end
end

function Card:set_rental(_rental)
    self.ability.rental = _rental
    self:set_cost()
end

function Card:set_debuff(should_debuff)
	for _, mod in ipairs(SMODS.mod_list) do
		if mod.set_debuff and type(mod.set_debuff) == 'function' then
            local res = mod.set_debuff(self)
            if res == 'prevent_debuff' then
                if self.debuff then
                    self.debuff = false
                    if self.area == G.jokers then self:add_to_deck(true) end
					self.debuffed_by_blind = false
                end
                return
            end
			should_debuff = should_debuff or res
		end
	end
	for k, v in pairs(self.ability.debuff_sources or {}) do
		if v == 'prevent_debuff' then
			if self.debuff then
				self.debuff = false
				if self.area == G.jokers then self:add_to_deck(true) end
			end
			self.debuffed_by_blind = false
			return
		end
		should_debuff = should_debuff or v
	end
	
    if self.ability.perishable and not self.ability.perish_tally then self.ability.perish_tally = G.GAME.perishable_rounds end
    if self.ability.perishable and self.ability.perish_tally <= 0 then 
        if not self.debuff then
            self.debuff = true
            if self.area == G.jokers then self:remove_from_deck(true) end
        end
        return
    end
    if should_debuff ~= self.debuff then
        if self.area == G.jokers then if should_debuff then self:remove_from_deck(true) else self:add_to_deck(true) end end
        self.debuff = should_debuff
    end
    if not self.debuff then self.debuffed_by_blind = false end
    
end

function Card:remove_UI()
    self.ability_UIBox_table = nil
    self.config.h_popup = nil
    self.config.h_popup_config = nil
    self.no_ui = true
end

function Card:change_suit(new_suit)
    local new_code = SMODS.Suits[new_suit].card_key
    local new_val = SMODS.Ranks[self.base.value].card_key
    local new_card = G.P_CARDS[new_code..'_'..new_val]

    self:set_base(new_card)
    G.GAME.blind:debuff_card(self)
end

function Card:add_to_deck(from_debuff)
    if not self.config.center.discovered then
        discover_card(self.config.center)
    end
    if not self.added_to_deck then
        self.added_to_deck = true
        if self.ability.set == 'Enhanced' or self.ability.set == 'Default' then 
            if self.ability.name == 'Gold Card' and self.seal == 'Gold' and self.playing_card then 
                check_for_unlock({type = 'double_gold'})
            end
            return 
        end

        if self.edition then
            if self.edition.type and G.P_CENTERS['e_'..(self.edition.type)] and not G.P_CENTERS['e_'..(self.edition.type)].discovered then
                discover_card(G.P_CENTERS['e_'..(self.edition.type)])
            end
        else
            if not G.P_CENTERS['e_base'].discovered then 
                discover_card(G.P_CENTERS['e_base'])
            end
        end
        local obj = self.config.center
        if obj and obj.add_to_deck and type(obj.add_to_deck) == 'function' then
            obj:add_to_deck(self, from_debuff)
        end        if self.ability.h_size ~= 0 then
            G.hand:change_size(self.ability.h_size)
        end
        if self.ability.d_size > 0 then
            G.GAME.round_resets.discards = G.GAME.round_resets.discards + self.ability.d_size
            ease_discard(self.ability.d_size)
        end
        if self.ability.name == 'Credit Card' then
            G.GAME.bankrupt_at = G.GAME.bankrupt_at - self.ability.extra
        end
        if self.ability.name == 'Chicot' and G.GAME.blind and G.GAME.blind.boss and not G.GAME.blind.disabled then
            G.GAME.blind:disable()
            play_sound('timpani')
            card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize('ph_boss_disabled')})
        end
        if self.ability.name == 'Chaos the Clown' then
            SMODS.change_free_rerolls(1)
            calculate_reroll_cost(true)
        end
        if self.ability.name == 'Turtle Bean' then
            G.hand:change_size(self.ability.extra.h_size)
        end
        if self.ability.name == 'Oops! All 6s' then
            for k, v in pairs(G.GAME.probabilities) do 
                G.GAME.probabilities[k] = v*2
            end
        end
        if self.ability.name == 'To the Moon' then
            G.GAME.interest_amount = G.GAME.interest_amount + self.ability.extra
        end
        if self.ability.name == 'Astronomer' then 
            G.E_MANAGER:add_event(Event({func = function()
                for k, v in pairs(G.I.CARD) do
                    if v.set_cost then v:set_cost() end
                end
                return true end }))
        end
        if self.ability.name == 'Troubadour' then
            G.hand:change_size(self.ability.extra.h_size)
            G.GAME.round_resets.hands = G.GAME.round_resets.hands + self.ability.extra.h_plays
        end
        if self.ability.name == 'Stuntman' then
            G.hand:change_size(-self.ability.extra.h_size)
        end
        if true then
            if from_debuff then
                self.ability.joker_added_to_deck_but_debuffed = nil
            else
                if self.edition and self.edition.card_limit then
                    if self.ability.consumeable then
                        G.consumeables.config.card_limit = G.consumeables.config.card_limit + self.edition.card_limit
                    else
                        G.jokers.config.card_limit = G.jokers.config.card_limit + self.edition.card_limit
                    end
                end
            end
        end
        if G.GAME.blind and G.GAME.blind.in_blind then G.E_MANAGER:add_event(Event({ func = function() G.GAME.blind:set_blind(nil, true, nil); return true end })) end
        if not from_debuff and G.jokers and #G.jokers.cards > 0 then
            for i = 1, #G.jokers.cards do
                G.jokers.cards[i]:calculate_joker({sdm_adding_card = true, card = self})
            end
        end
        
        if not from_debuff and G.hand then
            local is_playing_card = self.ability.set == 'Default' or self.ability.set == 'Enhanced'
            
            -- TARGET: calculate card_added
        
            if not is_playing_card then
                SMODS.calculate_context({card_added = true, card = self})
                SMODS.enh_cache:clear()
            end
        end
    end
end

function Card:remove_from_deck(from_debuff)
    if self.added_to_deck then
        self.added_to_deck = false
        local obj = self.config.center
        if obj and obj.remove_from_deck and type(obj.remove_from_deck) == 'function' then
            obj:remove_from_deck(self, from_debuff)
        end        if self.ability.h_size ~= 0 then
            G.hand:change_size(-self.ability.h_size)
        end
        if self.ability.d_size > 0 then
            G.GAME.round_resets.discards = G.GAME.round_resets.discards - self.ability.d_size
            ease_discard(-self.ability.d_size)
        end
        if self.ability.name == 'Credit Card' then
            G.GAME.bankrupt_at = G.GAME.bankrupt_at + self.ability.extra
        end
        if self.ability.name == 'Chaos the Clown' then
            SMODS.change_free_rerolls(-1)
            calculate_reroll_cost(true)
        end
        if self.ability.name == 'Turtle Bean' then
            G.hand:change_size(-self.ability.extra.h_size)
        end
        if self.ability.name == 'Oops! All 6s' then
            for k, v in pairs(G.GAME.probabilities) do 
                G.GAME.probabilities[k] = v/2
            end
        end
        if self.ability.name == 'To the Moon' then
            G.GAME.interest_amount = G.GAME.interest_amount - self.ability.extra
        end
        if self.ability.name == 'Astronomer' then 
            G.E_MANAGER:add_event(Event({func = function()
                for k, v in pairs(G.I.CARD) do
                    if v.set_cost then v:set_cost() end
                end
                return true end }))
        end
        if self.ability.name == 'Troubadour' then
            G.hand:change_size(-self.ability.extra.h_size)
            G.GAME.round_resets.hands = G.GAME.round_resets.hands - self.ability.extra.h_plays
        end
        if self.ability.name == 'Stuntman' then
            G.hand:change_size(self.ability.extra.h_size)
        end
        if G.jokers then
            if from_debuff then
                self.ability.joker_added_to_deck_but_debuffed = true
            else
                if self.edition and self.edition.card_limit then
                    if self.ability.consumeable then
                        G.consumeables.config.card_limit = G.consumeables.config.card_limit - self.edition.card_limit
                    elseif self.ability.set == 'Joker' then
                        G.jokers.config.card_limit = G.jokers.config.card_limit - self.edition.card_limit
                    end
                end 
            end
        end
        if G.GAME.blind and G.GAME.blind.in_blind then G.E_MANAGER:add_event(Event({ func = function() G.GAME.blind:set_blind(nil, true, nil); return true end })) end
    end
end

function Card:generate_UIBox_unlock_table(hidden)
    local loc_vars = {no_name = true, not_hidden = not hidden}

    return generate_card_ui(self.config.center, nil, loc_vars, 'Locked')
end

function Card:generate_UIBox_ability_table(vars_only)
    local card_type, hide_desc = self.ability.set or "None", nil
    local loc_vars = nil
    local main_start, main_end = nil,nil
    local no_badge = nil
    
    if not self.bypass_lock and self.config.center.unlocked ~= false and
    (self.ability.set == 'Joker' or self.ability.set == 'Edition' or self.ability.consumeable or self.ability.set == 'Voucher' or self.ability.set == 'Booster') and
    not self.config.center.discovered and 
    ((self.area ~= G.jokers and self.area ~= G.consumeables and self.area) or not self.area) then
        card_type = 'Undiscovered'
    end    
    if self.config.center.unlocked == false and not self.bypass_lock then --For everyting that is locked
        card_type = "Locked"
        if self.area and self.area == G.shop_demo then loc_vars = {}; no_badge = true end
    elseif card_type == 'Undiscovered' and not self.bypass_discovery_ui then -- Any Joker or tarot/planet/voucher that is not yet discovered
        hide_desc = true
    elseif self.debuff then
        loc_vars = { debuffed = true, playing_card = not not self.base.colour, value = self.base.value, suit = self.base.suit, colour = self.base.colour }
    elseif card_type == 'Default' or card_type == 'Enhanced' then
        local bonus_chips = self.ability.bonus + (self.ability.perma_bonus or 0)
        local total_h_dollars = self:get_h_dollars()
        loc_vars = { playing_card = not not self.base.colour, value = self.base.value, suit = self.base.suit, colour = self.base.colour,
                    nominal_chips = self.base.nominal > 0 and self.base.nominal or nil,
                    suitstats = G.GAME.suits[self.base.suit],
                    rankstats = G.GAME.ranks[self.base.value],
                    bonus_x_chips = self.ability.perma_x_chips ~= 0 and (self.ability.perma_x_chips + 1) or nil,
                    bonus_mult = self.ability.perma_mult ~= 0 and self.ability.perma_mult or nil,
                    bonus_x_mult = self.ability.perma_x_mult ~= 0 and (self.ability.perma_x_mult + 1) or nil,
                    bonus_h_chips = self.ability.perma_h_chips ~= 0 and self.ability.perma_h_chips or nil,
                    bonus_h_x_chips = self.ability.perma_h_x_chips ~= 0 and (self.ability.perma_h_x_chips + 1) or nil,
                    bonus_h_mult = self.ability.perma_h_mult ~= 0 and self.ability.perma_h_mult or nil,
                    bonus_h_x_mult = self.ability.perma_h_x_mult ~= 0 and (self.ability.perma_h_x_mult + 1) or nil,
                    bonus_p_dollars = self.ability.perma_p_dollars ~= 0 and self.ability.perma_p_dollars or nil,
                    bonus_h_dollars = self.ability.perma_h_dollars ~= 0 and self.ability.perma_h_dollars or nil,
                    total_h_dollars = total_h_dollars ~= 0 and total_h_dollars or nil,
                    bonus_chips = bonus_chips ~= 0 and bonus_chips or nil,
                }
    elseif self.ability.set == 'Joker' then -- all remaining jokers
        if self.ability.name == 'Joker' then loc_vars = {self.ability.mult}
        elseif self.ability.name == 'Jolly Joker' or self.ability.name == 'Zany Joker' or
            self.ability.name == 'Mad Joker' or self.ability.name == 'Crazy Joker'  or 
            self.ability.name == 'Droll Joker' then 
            loc_vars = {self.ability.t_mult, localize(self.ability.type, 'poker_hands')}
        elseif self.ability.name == 'Sly Joker' or self.ability.name == 'Wily Joker' or
        self.ability.name == 'Clever Joker' or self.ability.name == 'Devious Joker'  or 
        self.ability.name == 'Crafty Joker' then 
            loc_vars = {self.ability.t_chips, localize(self.ability.type, 'poker_hands')}
        elseif self.ability.name == 'Half Joker' then loc_vars = {self.ability.extra.mult, self.ability.extra.size}
        elseif self.ability.name == 'Fortune Teller' then loc_vars = {self.ability.extra, (G.GAME.consumeable_usage_total and G.GAME.consumeable_usage_total.tarot or 0)}
        elseif self.ability.name == 'Steel Joker' then loc_vars = {self.ability.extra, 1 + self.ability.extra*(self.ability.steel_tally or 0)}
        elseif self.ability.name == 'Chaos the Clown' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Space Joker' then loc_vars = {cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged), self.ability.extra}
        elseif self.ability.name == 'Stone Joker' then loc_vars = {self.ability.extra, self.ability.extra*(self.ability.stone_tally or 0)}
        elseif self.ability.name == 'Drunkard' then loc_vars = {self.ability.d_size}
        elseif self.ability.name == 'Green Joker' then loc_vars = {self.ability.extra.hand_add, self.ability.extra.discard_sub, self.ability.mult}
        elseif self.ability.name == 'Credit Card' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Greedy Joker' or self.ability.name == 'Lusty Joker' or
            self.ability.name == 'Wrathful Joker' or self.ability.name == 'Gluttonous Joker' then loc_vars = {self.ability.extra.s_mult, localize(self.ability.extra.suit, 'suits_singular')}
        elseif self.ability.name == 'Blue Joker' then loc_vars = {self.ability.extra, self.ability.extra*((G.deck and G.deck.cards) and #G.deck.cards or 52)}
        elseif self.ability.name == 'Sixth Sense' then loc_vars = {}
        elseif self.ability.name == 'Mime' then
        elseif self.ability.name == 'Hack' then loc_vars = {self.ability.extra+1}
        elseif self.ability.name == 'Pareidolia' then 
        elseif self.ability.name == 'Faceless Joker' then loc_vars = {self.ability.extra.dollars, self.ability.extra.faces}
        elseif self.ability.name == 'Oops! All 6s' then
        elseif self.ability.name == 'Juggler' then loc_vars = {self.ability.h_size}
        elseif self.ability.name == 'Golden Joker' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Joker Stencil' then loc_vars = {self.ability.x_mult}
        elseif self.ability.name == 'Four Fingers' then
        elseif self.ability.name == 'Ceremonial Dagger' then loc_vars = {self.ability.mult}
        elseif self.ability.name == 'Banner' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Misprint' then
            local r_mults = {}
            if self.ability.extra.max - self.ability.extra.min < 500 then
            	for i = self.ability.extra.min, self.ability.extra.max do
            	    r_mults[#r_mults+1] = tostring(i)
            	end
            else
            	for i = 1, 50 do
            		r_mults[#r_mults+1] = tostring(math.random(self.ability.extra.min, self.ability.extra.max))
            	end
            end
            
            local loc_mult = ' '..(localize('k_mult'))..' '
            main_start = {
                {n=G.UIT.T, config={text = '  +',colour = G.C.MULT, scale = 0.32}},
                {n=G.UIT.O, config={object = DynaText({string = r_mults, colours = {G.C.RED},pop_in_rate = 9999999, silent = true, random_element = true, pop_delay = 0.5, scale = 0.32, min_cycle_time = 0})}},
                {n=G.UIT.O, config={object = DynaText({string = {
                    {string = 'rand()', colour = G.C.JOKER_GREY},{string = "#@"..(G.deck and G.deck.cards[1] and G.deck.cards[#G.deck.cards].base.id or 11)..(G.deck and G.deck.cards[1] and G.deck.cards[#G.deck.cards].base.suit:sub(1,1) or 'D'), colour = G.C.RED},
                    loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult, loc_mult},
                colours = {G.C.UI.TEXT_DARK},pop_in_rate = 9999999, silent = true, random_element = true, pop_delay = 0.2011, scale = 0.32, min_cycle_time = 0})}},
            }
        elseif self.ability.name == 'Mystic Summit' then loc_vars = {self.ability.extra.mult, self.ability.extra.d_remaining}
        elseif self.ability.name == 'Marble Joker' then
        elseif self.ability.name == 'Loyalty Card' then loc_vars = {self.ability.extra.Xmult, self.ability.extra.every + 1, localize{type = 'variable', key = (self.ability.loyalty_remaining == 0 and 'loyalty_active' or 'loyalty_inactive'), vars = {self.ability.loyalty_remaining}}}
        elseif self.ability.name == '8 Ball' then loc_vars = {cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged),self.ability.extra}
        elseif self.ability.name == 'Dusk' then loc_vars = {self.ability.extra+1}
        elseif self.ability.name == 'Raised Fist' then
        elseif self.ability.name == 'Fibonacci' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Scary Face' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Abstract Joker' then loc_vars = {self.ability.extra, (G.jokers and G.jokers.cards and #G.jokers.cards or 0)*self.ability.extra}
        elseif self.ability.name == 'Delayed Gratification' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Gros Michel' then loc_vars = {self.ability.extra.mult, cry_prob(self.ability.cry_prob, self.ability.extra.odds, self.ability.cry_rigged), self.ability.extra.odds}
        elseif self.ability.name == 'Even Steven' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Odd Todd' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Scholar' then loc_vars = {self.ability.extra.mult, self.ability.extra.chips}
        elseif self.ability.name == 'Business Card' then loc_vars = {cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged),self.ability.extra}
        elseif self.ability.name == 'Supernova' then
        elseif self.ability.name == 'Spare Trousers' then loc_vars = {self.ability.extra, localize('Two Pair', 'poker_hands'), self.ability.mult}
        elseif self.ability.name == 'Superposition' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Ride the Bus' then loc_vars = {self.ability.extra, self.ability.mult}
        elseif self.ability.name == 'Egg' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Burglar' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Blackboard' then loc_vars = {self.ability.extra, localize('Spades', 'suits_plural'), localize('Clubs', 'suits_plural')}
        elseif self.ability.name == 'Runner' then loc_vars = {self.ability.extra.chips, self.ability.extra.chip_mod}
        elseif self.ability.name == 'Ice Cream' then loc_vars = {self.ability.extra.chips, self.ability.extra.chip_mod}
        elseif self.ability.name == 'DNA' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Splash' then
        elseif self.ability.name == 'Constellation' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Hiker' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'To Do List' then loc_vars = {self.ability.extra.dollars, localize(self.ability.to_do_poker_hand, 'poker_hands')}
        elseif self.ability.name == 'Smeared Joker' then
        elseif self.ability.name == 'Blueprint' then
            self.ability.blueprint_compat_ui = self.ability.blueprint_compat_ui or ''; self.ability.blueprint_compat_check = nil
            main_end = (self.area and self.area == G.jokers) and {
                {n=G.UIT.C, config={align = "bm", minh = 0.4}, nodes={
                    {n=G.UIT.C, config={ref_table = self, align = "m", colour = G.C.JOKER_GREY, r = 0.05, padding = 0.06, func = 'blueprint_compat'}, nodes={
                        {n=G.UIT.T, config={ref_table = self.ability, ref_value = 'blueprint_compat_ui',colour = G.C.UI.TEXT_LIGHT, scale = 0.32*0.8}},
                    }}
                }}
            } or nil
        elseif self.ability.name == 'Cartomancer' then
        elseif self.ability.name == 'Astronomer' then loc_vars = {self.ability.extra}
        
        elseif self.ability.name == 'Golden Ticket' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Mr. Bones' then
        elseif self.ability.name == 'Acrobat' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Sock and Buskin' then loc_vars = {self.ability.extra+1}
        elseif self.ability.name == 'Swashbuckler' then loc_vars = {self.ability.mult}
        elseif self.ability.name == 'Troubadour' then loc_vars = {self.ability.extra.h_size, -self.ability.extra.h_plays}
        elseif self.ability.name == 'Certificate' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Throwback' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Hanging Chad' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Rough Gem' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Bloodstone' then loc_vars = {cry_prob(self.ability.cry_prob, self.ability.extra.odds, self.ability.cry_rigged), self.ability.extra.odds, self.ability.extra.Xmult}
        elseif self.ability.name == 'Arrowhead' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Onyx Agate' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Glass Joker' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Showman' then
        elseif self.ability.name == 'Flower Pot' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Wee Joker' then loc_vars = {self.ability.extra.chips, self.ability.extra.chip_mod}
        elseif self.ability.name == 'Merry Andy' then loc_vars = {self.ability.d_size, self.ability.h_size}
        elseif self.ability.name == 'The Idol' then loc_vars = {self.ability.extra, localize(G.GAME.current_round.idol_card.rank, 'ranks'), localize(G.GAME.current_round.idol_card.suit, 'suits_plural'), colours = {G.C.SUITS[G.GAME.current_round.idol_card.suit]}}
        elseif self.ability.name == 'Seeing Double' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Matador' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Hit the Road' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'The Duo' or self.ability.name == 'The Trio'
            or self.ability.name == 'The Family' or self.ability.name == 'The Order' or self.ability.name == 'The Tribe' then loc_vars = {self.ability.x_mult, localize(self.ability.type, 'poker_hands')}
        
        elseif self.ability.name == 'Cavendish' then loc_vars = {self.ability.extra.Xmult, cry_prob(self.ability.cry_prob, self.ability.extra.odds, self.ability.cry_rigged), self.ability.extra.odds}
        elseif self.ability.name == 'Card Sharp' then loc_vars = {self.ability.extra.Xmult}
        elseif self.ability.name == 'Red Card' then loc_vars = {self.ability.extra, self.ability.mult}
        elseif self.ability.name == 'Madness' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Square Joker' then loc_vars = {self.ability.extra.chips, self.ability.extra.chip_mod}
        elseif self.ability.name == 'Seance' then loc_vars = {localize(self.ability.extra.poker_hand, 'poker_hands')}
        elseif self.ability.name == 'Riff-raff' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Vampire' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Shortcut' then
        elseif self.ability.name == 'Hologram' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Vagabond' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Baron' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Cloud 9' then loc_vars = {self.ability.extra, self.ability.extra*(self.ability.nine_tally or 0)}
        elseif self.ability.name == 'Rocket' then loc_vars = {self.ability.extra.dollars, self.ability.extra.increase}
        elseif self.ability.name == 'Obelisk' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Midas Mask' then
        elseif self.ability.name == 'Luchador' then
            local has_message= (G.GAME and self.area and (self.area == G.jokers))
            if has_message then
                local disableable = G.GAME.blind and ((not G.GAME.blind.disabled) and (G.GAME.blind:get_type() == 'Boss'))
                main_end = {
                    {n=G.UIT.C, config={align = "bm", minh = 0.4}, nodes={
                        {n=G.UIT.C, config={ref_table = self, align = "m", colour = disableable and G.C.GREEN or G.C.RED, r = 0.05, padding = 0.06}, nodes={
                            {n=G.UIT.T, config={text = ' '..localize(disableable and 'k_active' or 'ph_no_boss_active')..' ',colour = G.C.UI.TEXT_LIGHT, scale = 0.32*0.9}},
                        }}
                    }}
                }
            end
        elseif self.ability.name == 'Photograph' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Gift Card' then  loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Turtle Bean' then loc_vars = {self.ability.extra.h_size, self.ability.extra.h_mod}
        elseif self.ability.name == 'Erosion' then loc_vars = {self.ability.extra, math.max(0,self.ability.extra*(G.playing_cards and (G.GAME.starting_deck_size - #G.playing_cards) or 0)), G.GAME.starting_deck_size}
        elseif self.ability.name == 'Reserved Parking' then loc_vars = {self.ability.extra.dollars, cry_prob(self.ability.cry_prob, self.ability.extra.odds, self.ability.cry_rigged), self.ability.extra.odds}
        elseif self.ability.name == 'Mail-In Rebate' then loc_vars = {self.ability.extra, localize(G.GAME.current_round.mail_card.rank, 'ranks')}
        elseif self.ability.name == 'To the Moon' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Hallucination' then loc_vars = {cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged), self.ability.extra}
        elseif self.ability.name == 'Lucky Cat' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Baseball Card' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Bull' then loc_vars = {self.ability.extra, self.ability.extra*math.max(0,G.GAME.dollars) or 0}
        elseif self.ability.name == 'Diet Cola' then loc_vars = {localize{type = 'name_text', set = 'Tag', key = 'tag_double', nodes = {}}}
        elseif self.ability.name == 'Trading Card' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Flash Card' then loc_vars = {self.ability.extra, self.ability.mult}
        elseif self.ability.name == 'Popcorn' then loc_vars = {self.ability.mult, self.ability.extra}
        elseif self.ability.name == 'Ramen' then loc_vars = {self.ability.x_mult, self.ability.extra}
        elseif self.ability.name == 'Ancient Joker' then loc_vars = {self.ability.extra, localize(G.GAME.current_round.ancient_card.suit, 'suits_singular'), colours = {G.C.SUITS[G.GAME.current_round.ancient_card.suit]}}
        elseif self.ability.name == 'Walkie Talkie' then loc_vars = {self.ability.extra.chips, self.ability.extra.mult}
        elseif self.ability.name == 'Seltzer' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Castle' then loc_vars = {self.ability.extra.chip_mod, localize(G.GAME.current_round.castle_card.suit, 'suits_singular'), self.ability.extra.chips, colours = {G.C.SUITS[G.GAME.current_round.castle_card.suit]}}
        elseif self.ability.name == 'Smiley Face' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Campfire' then loc_vars = {self.ability.extra, self.ability.x_mult}
        elseif self.ability.name == 'Stuntman' then loc_vars = {self.ability.extra.chip_mod, self.ability.extra.h_size}
        elseif self.ability.name == 'Invisible Joker' then loc_vars = {self.ability.extra, self.ability.invis_rounds}
        elseif self.ability.name == 'Brainstorm' then
            self.ability.blueprint_compat_ui = self.ability.blueprint_compat_ui or ''; self.ability.blueprint_compat_check = nil
            main_end = (self.area and self.area == G.jokers) and {
                {n=G.UIT.C, config={align = "bm", minh = 0.4}, nodes={
                    {n=G.UIT.C, config={ref_table = self, align = "m", colour = G.C.JOKER_GREY, r = 0.05, padding = 0.06, func = 'blueprint_compat'}, nodes={
                        {n=G.UIT.T, config={ref_table = self.ability, ref_value = 'blueprint_compat_ui',colour = G.C.UI.TEXT_LIGHT, scale = 0.32*0.8}},
                    }}
                }}
            } or nil
        elseif self.ability.name == 'Satellite' then
            local planets_used = 0
            for k, v in pairs(G.GAME.consumeable_usage) do if v.set == 'Planet' then planets_used = planets_used + 1 end end
            loc_vars = {self.ability.extra, planets_used*self.ability.extra}
        elseif self.ability.name == 'Shoot the Moon' then loc_vars = {self.ability.extra}
        elseif self.ability.name == "Driver's License" then loc_vars = {self.ability.extra, self.ability.driver_tally or '0'}
        elseif self.ability.name == 'Burnt Joker' then
        elseif self.ability.name == 'Bootstraps' then loc_vars = {self.ability.extra.mult, self.ability.extra.dollars, self.ability.extra.mult*math.floor((G.GAME.dollars + (G.GAME.dollar_buffer or 0))/self.ability.extra.dollars)}
        elseif self.ability.name == 'Caino' then loc_vars = {self.ability.extra, self.ability.caino_xmult}
        elseif self.ability.name == 'Triboulet' then loc_vars = {self.ability.extra}
        elseif self.ability.name == 'Yorick' then loc_vars = {self.ability.extra.xmult, self.ability.extra.discards, self.ability.yorick_discards, self.ability.x_mult}
        elseif self.ability.name == 'Chicot' then
        elseif self.ability.name == 'Perkeo' then loc_vars = {self.ability.extra}
        end
    end
    if vars_only then return loc_vars, main_start, main_end end
    local badges = {}
    if (card_type ~= 'Locked' and card_type ~= 'Undiscovered' and card_type ~= 'Default') or self.debuff then
        badges.card_type = card_type
    end
    if self.ability.set == 'Joker' and self.bypass_discovery_ui and (not no_badge) then
        badges.force_rarity = true
    end
    if self.edition then
        if self.edition.type == 'negative' and self.ability.consumeable then
            badges[#badges + 1] = 'negative_consumable'
            elseif self.edition.type == 'negative' and (self.ability.set == 'Enhanced' or self.ability.set == 'Default') then
                badges[#badges + 1] = 'negative_playing_card'
        else
            badges[#badges + 1] = (self.edition.type == 'holo' and 'holographic' or self.edition.type)
        end
    end
    if self.seal then badges[#badges + 1] = string.lower(self.seal)..'_seal' end
    if not self.ability.cry_absolute then
    	if self.ability.eternal then badges[#badges + 1] = 'eternal' end
    end
    if self.ability.perishable and not layer then
        loc_vars = loc_vars or {}; loc_vars.perish_tally=self.ability.perish_tally
        badges[#badges + 1] = 'perishable'
    end
    if self.ability.rental then badges[#badges + 1] = 'rental' end
    -- if self.pinned then badges[#badges + 1] = 'pinned_left' end
    for k, v in ipairs(SMODS.Sticker.obj_buffer) do
    	if self.ability[v] and not SMODS.Stickers[v].hide_badge then
            badges[#badges+1] = v
        end
    end
    if self.sticker or ((self.sticker_run and self.sticker_run~='NONE') and G.SETTINGS.run_stake_stickers)  then loc_vars = loc_vars or {}; loc_vars.sticker=(self.sticker or self.sticker_run) end

    if card_type ~= 'Default' and card_type ~= 'Enhanced' and self.playing_card then
    	loc_vars = loc_vars or {}
    	loc_vars.ccd = {
    		playing_card = not not self.base.colour, value = self.base.value, suit = self.base.suit, colour = self.base.colour,
    		nominal_chips = self.base.nominal > 0 and self.base.nominal or nil,
    		suitstats = G.GAME.suits[self.base.suit],
    		rankstats = G.GAME.ranks[self.base.value],
    		bonus_chips = (self.ability.bonus + (self.ability.perma_bonus or 0)) > 0 and (self.ability.bonus + (self.ability.perma_bonus or 0)) or nil,
    	}
    end
    return generate_card_ui(self.config.center, nil, loc_vars, card_type, badges, hide_desc, main_start, main_end, self)
end

function Card:get_nominal(mod)
    local mult = 1
    local rank_mult = 1
    if mod == 'suit' then mult = 10000 end
    if self.ability.effect == 'Stone Card' or (self.config.center.no_suit and self.config.center.no_rank) then
        mult = -10000
    elseif self.config.center.no_suit then
        mult = 0
    elseif self.config.center.no_rank then
        rank_mult = 0
    end
    return 10*self.base.nominal*rank_mult + self.base.suit_nominal*mult + (self.base.suit_nominal_original or 0)*0.0001*mult + 10*self.base.face_nominal*rank_mult + 0.000001*self.unique_val
end

function Card:get_id()
    if SMODS.has_no_rank(self) and not self.vampired then
        return -math.random(100, 1000000)
    end
    return self.base.id
end

function Card:is_face(from_boss)
    if self.debuff and not from_boss then return end
    local id = self:get_id()
    local rank = SMODS.Ranks[self.base.value]
    if not id then return end
    if (id > 0 and rank and rank.face) or next(find_joker("Pareidolia")) then
        return true
    end
end

function Card:get_original_rank()
    return self.base.original_value
end

function Card:get_chip_bonus()

    if self.ability.effect == 'Stone Card' or self.config.center.replace_base_card then
        return self.ability.bonus + (self.ability.perma_bonus or 0)
    end
    return self.base.nominal + self.ability.bonus + (self.ability.perma_bonus or 0)
end

function Card:get_chip_mult()

    if self.ability.set == 'Joker' then return 0 end
    local ret = self.ability.perma_mult or 0
    if self.ability.effect == "Lucky Card" then
        if pseudorandom('lucky_mult') < cry_prob(self.ability.cry_prob, 5, self.ability.cry_rigged)/5 then
            self.lucky_trigger = true
            ret = ret + self.ability.mult
        end
    else
        ret = ret + self.ability.mult
    end
    -- TARGET: get_chip_mult
    return ret
end

function Card:get_chip_x_mult(context)

    if self.ability.set == 'Joker' then return 0 end
    local ret = SMODS.multiplicative_stacking(self.ability.x_mult or 1, self.ability.perma_x_mult or 0)
    -- TARGET: get_chip_x_mult
    return ret
end

function Card:get_chip_h_mult()

    local ret = (self.ability.h_mult or 0) + (self.ability.perma_h_mult or 0)
    -- TARGET: get_chip_h_mult
    return ret
end

function Card:get_chip_h_x_mult()

    local ret = SMODS.multiplicative_stacking(self.ability.h_x_mult or 1, self.ability.perma_h_x_mult or 0)
    -- TARGET: get_chip_h_x_mult
    return ret
end

function Card:get_chip_x_bonus()
    if self.debuff then return 0 end
    local ret = SMODS.multiplicative_stacking(self.ability.x_chips or 1, self.ability.perma_x_chips or 0)
    -- TARGET: get_chip_x_bonus
    return ret
end

function Card:get_chip_h_bonus()
    if self.debuff then return 0 end
    local ret = (self.ability.h_chips or 0) + (self.ability.perma_h_chips or 0)
    -- TARGET: get_chip_h_bonus
    return ret
end

function Card:get_chip_h_x_bonus()
    if self.debuff then return 0 end
    local ret = SMODS.multiplicative_stacking(self.ability.h_x_chips or 1, self.ability.perma_h_x_chips or 0)
    -- TARGET: get_chip_h_x_bonus
    return ret
end

function Card:get_h_dollars()
    if self.debuff then return 0 end
    local ret = (self.ability.h_dollars or 0) + (self.ability.perma_h_dollars or 0)
    -- TARGET: get_h_dollars
    return ret
end
function Card:get_edition()
    if self.debuff then return end
    if self.edition then
        local ret = {card = self}
        if self.edition.x_mult then 
            ret.x_mult_mod = self.edition.x_mult
        end
        if self.edition.mult then 
            ret.mult_mod = self.edition.mult
        end
        if self.edition.chips then 
            ret.chip_mod = self.edition.chips
        end
        return ret
    end
end

function Card:get_end_of_round_effect(context)
    local ret = {}
    local h_dollars = self:get_h_dollars()
    if h_dollars ~= 0 then
        ret.h_dollars = h_dollars
        ret.card = self
    end
    if self.seal == 'Blue' and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit and not self.ability.extra_enhancement then
        local card_type = 'Planet'
        G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
        G.E_MANAGER:add_event(Event({
            trigger = 'before',
            delay = 0.0,
            func = (function()
                if G.GAME.last_hand_played then
                    local _planet = 0
                    for k, v in pairs(G.P_CENTER_POOLS.Planet) do
                        if v.config.hand_type == G.GAME.last_hand_played then
                            _planet = v.key
                        end
                    end
                    local card = create_card(card_type,G.consumeables, nil, nil, nil, nil, _planet, 'blusl')
                    card:add_to_deck()
                    G.consumeables:emplace(card)
                    G.GAME.consumeable_buffer = 0
                end
                return true
            end)}))
        card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize('k_plus_planet'), colour = G.C.SECONDARY_SET.Planet})
        ret.effect = true
    end
    return ret
end


function Card:get_p_dollars()

    local ret = 0
    local obj = G.P_SEALS[self.seal] or {}
    if obj.get_p_dollars and type(obj.get_p_dollars) == 'function' then
        ret = ret + obj:get_p_dollars(self)
    elseif self.seal == 'Gold' then
        ret = ret +  3
    end
    if self.ability.p_dollars > 0 then
        if self.ability.effect == "Lucky Card" then 
            if pseudorandom('lucky_money') < cry_prob(self.ability.cry_prob, 15, self.ability.cry_rigged)/15 then
                self.lucky_trigger = true
                ret = ret +  self.ability.p_dollars
            end
        else 
            ret = ret + self.ability.p_dollars
        end
    elseif self.ability.p_dollars < 0 then
        ret = ret + self.ability.p_dollars
    end
    ret = ret + (self.ability.perma_p_dollars) or 0
    -- TARGET: get_p_dollars
    if ret ~= 0 then
        G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + ret
        if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
    end
    return ret
end

function Card:use_consumeable(area, copier)
    stop_use()
    if not copier then set_consumeable_usage(self) end
    if self.debuff then return nil end
    local used_tarot = copier or self
    if self.ability.rental then
    	G.E_MANAGER:add_event(Event({
    		trigger = 'immediate',
    		blocking = false,
    		blockable = false,
    		func = (function()
    			ease_dollars(-G.GAME.cry_consumeable_rental_rate)
    		return true
    	end)}))
    end
    local gone = false
    if self.ability.banana then
        if not self.ability.extinct then
            if (pseudorandom('oops_it_banana') < G.GAME.probabilities.normal/G.GAME.cry_consumeable_banana_odds) then
    	    local gone = true
                self.ability.extinct = true
                G.E_MANAGER:add_event(Event({
                    func = function()
                        play_sound('tarot1')
                        self.T.r = -0.2
                        self:juice_up(0.3, 0.4)
                        self.states.drag.is = true
                        self.children.center.pinch.x = true
                        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, blockable = false,
                            func = function()
                                    if self.area then self.area:remove_card(self) end
                                    self:remove()
                                    self = nil
                                return true; end}))
                        return true
                    end
                }))
                card_eval_status_text(self, 'jokers', nil, nil, nil, {message = localize('k_extinct_ex'), delay = 0.1})
                return true
            end
        end
    end
    if gone == false then

    if self.ability.consumeable.max_highlighted then
        update_hand_text({immediate = true, nopulse = true, delay = 0}, {mult = 0, chips = 0, level = '', handname = ''})
    end

    local obj = self.config.center
    if obj.use and type(obj.use) == 'function' then
        obj:use(self, area, copier)
        return
    end    if self.ability.consumeable.mod_conv or self.ability.consumeable.suit_conv then
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            play_sound('tarot1')
            used_tarot:juice_up(0.3, 0.5)
            return true end }))
        for i=1, #G.hand.highlighted do
            local percent = 1.15 - (i-0.999)/(#G.hand.highlighted-0.998)*0.3
            G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.15,func = function() G.hand.highlighted[i]:flip();play_sound('card1', percent);G.hand.highlighted[i]:juice_up(0.3, 0.3);return true end }))
        end
        delay(0.2)
        if self.ability.name == 'Death' then
            local rightmost = G.hand.highlighted[1]
            for i=1, #G.hand.highlighted do if G.hand.highlighted[i].T.x > rightmost.T.x then rightmost = G.hand.highlighted[i] end end
            for i=1, #G.hand.highlighted do
                G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.1,func = function()
                    if G.hand.highlighted[i] ~= rightmost and not G.hand.highlighted[i].ability.eternal then
                        copy_card(rightmost, G.hand.highlighted[i])
                    end
                    return true end }))
            end  
        elseif self.ability.name == 'Strength' then
            for i=1, #G.hand.highlighted do
                G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.1,func = function()
                    local card = G.hand.highlighted[i]
                    local suit_prefix = string.sub(card.base.suit, 1, 1)..'_'
                    local rank_suffix = card.base.id == 14 and 2 or math.min(card.base.id+1, 14)
                    if rank_suffix < 10 then rank_suffix = tostring(rank_suffix)
                    elseif rank_suffix == 10 then rank_suffix = 'T'
                    elseif rank_suffix == 11 then rank_suffix = 'J'
                    elseif rank_suffix == 12 then rank_suffix = 'Q'
                    elseif rank_suffix == 13 then rank_suffix = 'K'
                    elseif rank_suffix == 14 then rank_suffix = 'A'
                    end
                    card:set_base(G.P_CARDS[suit_prefix..rank_suffix])
                return true end }))
            end  
        elseif self.ability.consumeable.suit_conv then
            for i=1, #G.hand.highlighted do
                G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.1,func = function() G.hand.highlighted[i]:change_suit(self.ability.consumeable.suit_conv);return true end }))
            end    
        else
            for i=1, #G.hand.highlighted do
                G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.1,func = function() G.hand.highlighted[i]:set_ability(G.P_CENTERS[self.ability.consumeable.mod_conv]);return true end }))
            end 
        end
        for i=1, #G.hand.highlighted do
            local percent = 0.85 + (i-0.999)/(#G.hand.highlighted-0.998)*0.3
            G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.15,func = function() G.hand.highlighted[i]:flip();play_sound('tarot2', percent, 0.6);G.hand.highlighted[i]:juice_up(0.3, 0.3);return true end }))
        end
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2,func = function() G.hand:unhighlight_all(); return true end }))
        delay(0.5)
    end
    if self.ability.name == 'Black Hole' then
        update_hand_text({sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3}, {handname=localize('k_all_hands'),chips = '...', mult = '...', level=''})
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2, func = function()
            play_sound('tarot1')
            self:juice_up(0.8, 0.5)
            G.TAROT_INTERRUPT_PULSE = true
            return true end }))
        update_hand_text({delay = 0}, {mult = '+', StatusText = true})
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.9, func = function()
            play_sound('tarot1')
            self:juice_up(0.8, 0.5)
            return true end }))
        update_hand_text({delay = 0}, {chips = '+', StatusText = true})
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.9, func = function()
            play_sound('tarot1')
            self:juice_up(0.8, 0.5)
            G.TAROT_INTERRUPT_PULSE = nil
            return true end }))
        update_hand_text({sound = 'button', volume = 0.7, pitch = 0.9, delay = 0}, {level='+1'})
        delay(1.3)
        for k, v in pairs(G.GAME.hands) do
            level_up_hand(self, k, true)
        end
        update_hand_text({sound = 'button', volume = 0.7, pitch = 1.1, delay = 0}, {mult = 0, chips = 0, handname = '', level = ''})
    end
    if self.ability.name == 'Talisman' or self.ability.name == 'Deja Vu' or self.ability.name == 'Trance' or self.ability.name == 'Medium' then
        for q = 1, #G.hand.highlighted do
        local conv_card = G.hand.highlighted[q]
        G.E_MANAGER:add_event(Event({func = function()
            play_sound('tarot1')
            used_tarot:juice_up(0.3, 0.5)
            return true end }))
        
        G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.1,func = function()
            conv_card:set_seal(self.ability.extra, nil, true)
            return true end }))
        end
        delay(0.5)
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2,func = function() G.hand:unhighlight_all(); return true end }))
        end--[[
        G.E_MANAGER:add_event(Event({func = function()
            play_sound('tarot1')
            used_tarot:juice_up(0.3, 0.5)
            return true end }))
        
        G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.1,func = function()
            conv_card:set_seal(self.ability.extra, nil, true)
            return true end }))
        
        delay(0.5)
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2,func = function() G.hand:unhighlight_all(); return true end }))
    end
    --]]
    if self.ability.name == 'Aura' then 
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            local over = false
            local edition = poll_edition('aura', nil, true, true)
            local aura_card = G.hand.highlighted[1]
            aura_card:set_edition(edition, true)
            used_tarot:juice_up(0.3, 0.5)
        return true end }))
    end
    if self.ability.name == 'Cryptid' then
        G.E_MANAGER:add_event(Event({
            func = function()
                local _first_dissolve = nil
                local new_cards = {}
                for i = 1, self.ability.extra do
                    G.playing_card = (G.playing_card and G.playing_card + 1) or 1
                    for q = 1, #G.hand.highlighted do
                    local _card = copy_card(G.hand.highlighted[q], nil, nil, G.playing_card)
                    _card:add_to_deck()
                    G.deck.config.card_limit = G.deck.config.card_limit + 1
                    table.insert(G.playing_cards, _card)
                    G.hand:emplace(_card)
                    _card:start_materialize(nil, _first_dissolve)
                    _first_dissolve = true
                    if _card.config.center.key == "c_cryptid" then check_for_unlock({type = "cryptid_the_cryptid"}) end
                    new_cards[#new_cards+1] = _card
                    end
                end
                playing_card_joker_effects(new_cards)
                return true
            end
        })) 
    end
    if self.ability.name == 'Sigil' or self.ability.name == 'Ouija' then
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            play_sound('tarot1')
            used_tarot:juice_up(0.3, 0.5)
            return true end }))
        for i=1, #G.hand.cards do
            local percent = 1.15 - (i-0.999)/(#G.hand.cards-0.998)*0.3
            G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.15,func = function() G.hand.cards[i]:flip();play_sound('card1', percent);G.hand.cards[i]:juice_up(0.3, 0.3);return true end }))
        end
        delay(0.2)
        if self.ability.name == 'Sigil' then
            local _suit = pseudorandom_element({'S','H','D','C'}, pseudoseed('sigil'))
            for i=1, #G.hand.cards do
                G.E_MANAGER:add_event(Event({func = function()
                    local card = G.hand.cards[i]
                    local suit_prefix = _suit..'_'
                    local rank_suffix = card.base.id < 10 and tostring(card.base.id) or
                                        card.base.id == 10 and 'T' or card.base.id == 11 and 'J' or
                                        card.base.id == 12 and 'Q' or card.base.id == 13 and 'K' or
                                        card.base.id == 14 and 'A'
                    card:set_base(G.P_CARDS[suit_prefix..rank_suffix])
                return true end }))
            end  
        end
        if self.ability.name == 'Ouija' then
            local _rank = pseudorandom_element({'2','3','4','5','6','7','8','9','T','J','Q','K','A'}, pseudoseed('ouija'))
            for i=1, #G.hand.cards do
                G.E_MANAGER:add_event(Event({func = function()
                    local card = G.hand.cards[i]
                    local suit_prefix = string.sub(card.base.suit, 1, 1)..'_'
                    local rank_suffix =_rank
                    card:set_base(G.P_CARDS[suit_prefix..rank_suffix])
                return true end }))
            end  
            G.hand:change_size(-1)
        end
        for i=1, #G.hand.cards do
            local percent = 0.85 + (i-0.999)/(#G.hand.cards-0.998)*0.3
            G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.15,func = function() G.hand.cards[i]:flip();play_sound('tarot2', percent, 0.6);G.hand.cards[i]:juice_up(0.3, 0.3);return true end }))
        end
        delay(0.5)
    end
    if self.ability.consumeable.hand_type then
        update_hand_text({sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3}, {handname=localize(self.ability.consumeable.hand_type, 'poker_hands'),chips = G.GAME.hands[self.ability.consumeable.hand_type].chips, mult = G.GAME.hands[self.ability.consumeable.hand_type].mult, level=G.GAME.hands[self.ability.consumeable.hand_type].level})
        level_up_hand(used_tarot, self.ability.consumeable.hand_type)
        update_hand_text({sound = 'button', volume = 0.7, pitch = 1.1, delay = 0}, {mult = 0, chips = 0, handname = '', level = ''})
    end
    if self.ability.consumeable.remove_card then
        local destroyed_cards = {}
        if self.ability.name == 'The Hanged Man' then
            for i=#G.hand.highlighted, 1, -1 do
                destroyed_cards[#destroyed_cards+1] = G.hand.highlighted[i]
            end
            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
                play_sound('tarot1')
                used_tarot:juice_up(0.3, 0.5)
                return true end }))
            G.E_MANAGER:add_event(Event({
                trigger = 'after',
                delay = 0.2,
                func = function() 
                    for i=#G.hand.highlighted, 1, -1 do
                        local card = G.hand.highlighted[i]
                        if SMODS.shatters(card) then
                            card:shatter()
                        else
                            card:start_dissolve(nil, i == #G.hand.highlighted)
                        end
                    end
                    return true end }))
        elseif self.ability.name == 'Familiar' or self.ability.name == 'Grim' or self.ability.name == 'Incantation' then
            destroyed_cards[#destroyed_cards+1] = pseudorandom_element(G.hand.cards, pseudoseed('random_destroy'))
            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
                play_sound('tarot1')
                used_tarot:juice_up(0.3, 0.5)
                return true end }))
            G.E_MANAGER:add_event(Event({
                trigger = 'after',
                delay = 0.1,
                func = function() 
                    for i=#destroyed_cards, 1, -1 do
                        local card = destroyed_cards[i]
                        if SMODS.shatters(card) then
                            card:shatter()
                        else
                            card:start_dissolve(nil, i ~= #destroyed_cards)
                        end
                    end
                    return true end }))
            G.E_MANAGER:add_event(Event({
                trigger = 'after',
                delay = 0.7,
                func = function() 
                    local cards = {}
                    for i=1, self.ability.extra do
                        cards[i] = true
                        local _suit, _rank = nil, nil
                        if self.ability.name == 'Familiar' then
                            _rank = pseudorandom_element({'J', 'Q', 'K'}, pseudoseed('familiar_create'))
                            _suit = pseudorandom_element({'S','H','D','C'}, pseudoseed('familiar_create'))
                        elseif self.ability.name == 'Grim' then
                            _rank = 'A'
                            _suit = pseudorandom_element({'S','H','D','C'}, pseudoseed('grim_create'))
                        elseif self.ability.name == 'Incantation' then
                            _rank = pseudorandom_element({'2', '3', '4', '5', '6', '7', '8', '9', 'T'}, pseudoseed('incantation_create'))
                            _suit = pseudorandom_element({'S','H','D','C'}, pseudoseed('incantation_create'))
                        end
                        _suit = _suit or 'S'; _rank = _rank or 'A'
                        local cen_pool = {}
                        for k, v in pairs(G.P_CENTER_POOLS["Enhanced"]) do
                            if v.key ~= 'm_stone' then 
                                cen_pool[#cen_pool+1] = v
                            end
                        end
                        create_playing_card({front = G.P_CARDS[_suit..'_'.._rank], center = pseudorandom_element(cen_pool, pseudoseed('spe_card'))}, G.hand, nil, i ~= 1, {G.C.SECONDARY_SET.Spectral})
                    end
                    playing_card_joker_effects(cards)
                    return true end }))
        elseif self.ability.name == 'Immolate' then
            local temp_hand = {}
            for k, v in ipairs(G.hand.cards) do
                if not v.ability.eternal then
                    temp_hand[#temp_hand+1] = v
                end
            end
            table.sort(temp_hand, function (a, b) return not a.playing_card or not b.playing_card or a.playing_card < b.playing_card end)
            pseudoshuffle(temp_hand, pseudoseed('immolate'))

            for i = 1, self.ability.extra.destroy do destroyed_cards[#destroyed_cards+1] = temp_hand[i] end

            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
                play_sound('tarot1')
                used_tarot:juice_up(0.3, 0.5)
                return true end }))
            G.E_MANAGER:add_event(Event({
                trigger = 'after',
                delay = 0.1,
                func = function() 
                    for i=#destroyed_cards, 1, -1 do
                        local card = destroyed_cards[i]
                        if SMODS.shatters(card) then
                            card:shatter()
                        else
                            card:start_dissolve(nil, i == #destroyed_cards)
                        end
                    end
                    return true end }))
            delay(0.5)
            ease_dollars(self.ability.extra.dollars)
        end
        delay(0.3)
        SMODS.calculate_context({ remove_playing_cards = true, removed = destroyed_cards })
    end
    if self.ability.name == 'The Fool' then
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            if G.consumeables.config.card_limit > #G.consumeables.cards then
                play_sound('timpani')
                local card = create_card('Tarot_Planet', G.consumeables, nil, nil, nil, nil, G.GAME.last_tarot_planet, 'fool')
                card:add_to_deck()
                G.consumeables:emplace(card)
                used_tarot:juice_up(0.3, 0.5)
            end
            return true end }))
        delay(0.6)
    end
    if self.ability.name == 'The Hermit' then
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            play_sound('timpani')
            used_tarot:juice_up(0.3, 0.5)
            ease_dollars(math.max(0,math.min(G.GAME.dollars, self.ability.extra)), true)
            return true end }))
        delay(0.6)
    end
    if self.ability.name == 'Temperance' then
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            play_sound('timpani')
            used_tarot:juice_up(0.3, 0.5)
            ease_dollars(self.ability.money, true)
            return true end }))
        delay(0.6)
    end
    if self.ability.name == 'The Emperor' or self.ability.name == 'The High Priestess' then
        for i = 1, math.min((self.ability.consumeable.tarots or self.ability.consumeable.planets), G.consumeables.config.card_limit - #G.consumeables.cards) do
            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
                if G.consumeables.config.card_limit > #G.consumeables.cards then
                    play_sound('timpani')
                    local card = create_card((self.ability.name == 'The Emperor' and 'Tarot') or (self.ability.name == 'The High Priestess' and 'Planet'), G.consumeables, nil, nil, nil, nil, nil, (self.ability.name == 'The Emperor' and 'emp') or (self.ability.name == 'The High Priestess' and 'pri'))
                    card:add_to_deck()
                    G.consumeables:emplace(card)
                    used_tarot:juice_up(0.3, 0.5)
                end
                return true end }))
        end
        delay(0.6)
    end
    if self.ability.name == 'Judgement' or self.ability.name == 'The Soul' then
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            play_sound('timpani')
            local card = create_card('Joker', G.jokers, self.ability.name == 'The Soul', nil, nil, nil, nil, self.ability.name == 'Judgement' and 'jud' or 'sou')
            card:add_to_deck()
            G.jokers:emplace(card)
            if self.ability.name == 'The Soul' then check_for_unlock{type = 'spawn_legendary'} end
            used_tarot:juice_up(0.3, 0.5)
            return true end }))
        delay(0.6)
    end
    if self.ability.name == 'Ankh' then 
        --Need to check for edgecases - if there are max Jokers and all are eternal OR there is a max of 1 joker this isn't possible already
        --If there are max Jokers and exactly 1 is not eternal, that joker cannot be the one selected
        --otherwise, the selected joker can be totally random and all other non-eternal jokers can be removed
        local deletable_jokers = {}
        for k, v in pairs(G.jokers.cards) do
            if not v.ability.eternal then deletable_jokers[#deletable_jokers + 1] = v end
        end
        local chosen_joker = pseudorandom_element(G.jokers.cards, pseudoseed('ankh_choice'))
        local _first_dissolve = nil
        G.E_MANAGER:add_event(Event({trigger = 'before', delay = 0.75, func = function()
            for k, v in pairs(deletable_jokers) do
                if v ~= chosen_joker then 
                    v:start_dissolve(nil, _first_dissolve)
                    _first_dissolve = true
                end
            end
            return true end }))
        G.E_MANAGER:add_event(Event({trigger = 'before', delay = 0.4, func = function()
            local card = copy_card(chosen_joker, nil, nil, nil, chosen_joker.edition and chosen_joker.edition.negative)
            card:start_materialize()
            card:add_to_deck()
            if card.edition and card.edition.negative then
                card:set_edition(nil, true)
            end
            G.jokers:emplace(card)
            return true end }))
    end
    if self.ability.name == 'Wraith' then
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            play_sound('timpani')
            local card = create_card('Joker', G.jokers, nil, 0.99, nil, nil, nil, 'wra')
            card:add_to_deck()
            G.jokers:emplace(card)
            used_tarot:juice_up(0.3, 0.5)
            if G.GAME.dollars ~= 0 then
                ease_dollars(-G.GAME.dollars, true)
            end
            return true end }))
        delay(0.6)
    end
    if self.ability.name == 'The Wheel of Fortune' or self.ability.name == 'Ectoplasm' or self.ability.name == 'Hex' then
        local temp_pool =   (self.ability.name == 'The Wheel of Fortune' and self.eligible_strength_jokers) or 
                            ((self.ability.name == 'Ectoplasm' or self.ability.name == 'Hex') and self.eligible_editionless_jokers) or {}
        if self.ability.name == 'Ectoplasm' or self.ability.name == 'Hex' or pseudorandom('wheel_of_fortune') < cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged)/self.ability.extra then
if self.ability.name == 'The Wheel of Fortune' then self.cry_wheel_success = true end
            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
                local over = false
                local eligible_card = pseudorandom_element(temp_pool, pseudoseed(
                    (self.ability.name == 'The Wheel of Fortune' and 'wheel_of_fortune') or 
                    (self.ability.name == 'Ectoplasm' and 'ectoplasm') or
                    (self.ability.name == 'Hex' and 'hex')
                ))
                local edition = nil
                if self.ability.name == 'Ectoplasm' then
                    edition = {negative = true}
                elseif self.ability.name == 'Hex' then
                    edition = {polychrome = true}
                elseif self.ability.name == 'The Wheel of Fortune' then
                    edition = poll_edition('wheel_of_fortune', nil, true, true)
                end
                eligible_card:set_edition(edition, true)
                if self.ability.name == 'The Wheel of Fortune' or self.ability.name == 'Ectoplasm' or self.ability.name == 'Hex' then check_for_unlock({type = 'have_edition'}) end
                if self.ability.name == 'Hex' then 
                    local _first_dissolve = nil
                    for k, v in pairs(G.jokers.cards) do
                        if v ~= eligible_card and (not v.ability.eternal) then v:start_dissolve(nil, _first_dissolve);_first_dissolve = true end
                    end
                end
                if self.ability.name == 'Ectoplasm' then 
                    G.GAME.ecto_minus = G.GAME.ecto_minus or 1
                    G.hand:change_size(-G.GAME.ecto_minus)
                    G.GAME.ecto_minus = G.GAME.ecto_minus + 1
                end
                used_tarot:juice_up(0.3, 0.5)
            return true end }))
        else
            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
                attention_text({
                    text = localize('k_nope_ex'),
                    scale = 1.3, 
                    hold = 1.4,
                    major = used_tarot,
                    backdrop_colour = G.C.SECONDARY_SET.Tarot,
                    align = (G.STATE == G.STATES.TAROT_PACK or G.STATE == G.STATES.SPECTRAL_PACK or G.STATE == G.STATES.SMODS_BOOSTER_OPENED) and 'tm' or 'cm',
                    offset = {x = 0, y = (G.STATE == G.STATES.TAROT_PACK or G.STATE == G.STATES.SPECTRAL_PACK or G.STATE == G.STATES.SMODS_BOOSTER_OPENED) and -0.2 or 0},
                    silent = true
                    })
                    G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.06*G.SETTINGS.GAMESPEED, blockable = false, blocking = false, func = function()
                        play_sound('tarot2', 0.76, 0.4);return true end}))
                    play_sound('tarot2', 1, 0.4)
                    used_tarot:juice_up(0.3, 0.5)
            return true end }))
        end
        delay(0.6)
    end
end

end
function Card:can_use_consumeable(any_state, skip_check)
    if not skip_check and ((G.play and #G.play.cards > 0) or
        (G.CONTROLLER.locked) or
        (G.GAME.STOP_USE and G.GAME.STOP_USE > 0))
        then  return false end
    if G.GAME.cry_pinned_consumeables > 0 and not self.pinned then
    	return false
    end
    if G.STATE ~= G.STATES.HAND_PLAYED and G.STATE ~= G.STATES.DRAW_TO_HAND and G.STATE ~= G.STATES.PLAY_TAROT or any_state then

        local obj = self.config.center
        if obj.can_use and type(obj.can_use) == 'function' then
            return obj:can_use(self)
        end        if self.ability.name == 'The Hermit' or self.ability.consumeable.hand_type or self.ability.name == 'Temperance' or self.ability.name == 'Black Hole' then
            return true
        end
        if self.ability.name == 'The Wheel of Fortune' then 
            if next(self.eligible_strength_jokers) then return true end
        end
        if self.ability.name == 'Ankh' then
            --if there is at least one joker
            for k, v in pairs(G.jokers.cards) do
                if v.ability.set == 'Joker' and G.jokers.config.card_limit > 1 then 
                    return true
                end
            end
        end
        --]]
        if self.ability.name == 'Aura' then 
            if self.area ~= G.hand then
                return G.hand and (#G.hand.highlighted == 1) and G.hand.highlighted[1] and (not G.hand.highlighted[1].edition)
            else
                local idx = 1
                if G.hand.highlighted[1] == self then
                    local idx = 2
                end
                return (#G.hand.highlighted == 2) and (not G.hand.highlighted[idx].edition)
            end
        end
        if self.ability.name == 'Ectoplasm' or self.ability.name == 'Hex' then 
            if next(self.eligible_editionless_jokers) then return true end
        end
        if self.ability.name == 'The Emperor' or self.ability.name == 'The High Priestess'  then 
            if #G.consumeables.cards < G.consumeables.config.card_limit or self.area == G.consumeables then return true end
        end
        if self.ability.name == 'The Fool' then
            if (#G.consumeables.cards < G.consumeables.config.card_limit or self.area == G.consumeables) 
                and G.GAME.last_tarot_planet and G.GAME.last_tarot_planet ~= 'c_fool' then return true end
        end
        if self.ability.name == 'Judgement' or self.ability.name == 'The Soul' or self.ability.name == 'Wraith' then
            if #G.jokers.cards < G.jokers.config.card_limit or self.area == G.jokers then
                return true
            else
                return false
            end
        end
        if G.STATE == G.STATES.SELECTING_HAND or G.STATE == G.STATES.TAROT_PACK or G.STATE == G.STATES.SPECTRAL_PACK or G.STATE == G.STATES.PLANET_PACK or G.STATE == G.STATES.SMODS_BOOSTER_OPENED then
            if self.ability.consumeable.max_highlighted then
                if (self.ability.consumeable.mod_num - ((G.GAME.modifiers.cry_consumable_reduce and (self.ability.name ~= 'Death')) and (self.ability.consumeable.mod_num > 1) and 1 or 0)) >= #G.hand.highlighted + (self.area == G.hand and -1 or 0) and #G.hand.highlighted + (self.area == G.hand and -1 or 0) >= 1 then
                    return true
                end
            end
            if (self.ability.name == 'Familiar' or self.ability.name == 'Grim' or
                self.ability.name == 'Incantation' or self.ability.name == 'Immolate' or
                self.ability.name == 'Sigil' or self.ability.name == 'Ouija')
                and #G.hand.cards > 1 then
                return true
            end
        end
    end
    return false
end

function Card:check_use()
    if self.ability.name == 'Ankh' then 
        if #G.jokers.cards >= G.jokers.config.card_limit then  
            alert_no_space(self, G.jokers)
            return true
        end
    end
end

function Card:sell_card()
    G.CONTROLLER.locks.selling_card = true
    stop_use()
    local area = self.area
    G.CONTROLLER:save_cardarea_focus(area == G.jokers and 'jokers' or 'consumeables')

    if self.children.use_button then self.children.use_button:remove(); self.children.use_button = nil end
    if self.children.sell_button then self.children.sell_button:remove(); self.children.sell_button = nil end
    
    local eval, post = eval_card(self, {selling_self = true})
    local effects = {eval}
    for _,v in ipairs(post) do effects[#effects+1] = v end
    if eval.retriggers then
        for rt = 1, #eval.retriggers do
            local rt_eval, rt_post = eval_card(self, { selling_self = true, retrigger_joker = true})
            table.insert(effects, {eval.retriggers[rt]})
            table.insert(effects, rt_eval)
            for _, v in ipairs(rt_post) do effects[#effects+1] = v end
        end
    end
    SMODS.trigger_effects(effects, self)

    G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2,func = function()
        if (not G.GAME.modifiers.cry_no_sell_value) and self.sell_cost ~= 0 then
        	play_sound('coin2')
        end
        self:juice_up(0.3, 0.4)
        return true
    end}))
    delay(0.2)
    G.E_MANAGER:add_event(Event({trigger = 'immediate',func = function()
        if (not G.GAME.modifiers.cry_no_sell_value) and self.sell_cost ~= 0 then
        	ease_dollars(self.sell_cost)
        end
        if G.GAME.modifiers.cry_no_sell_value or self.sell_cost == 0 then
        	self:start_dissolve({G.C.RED})
        else
        	self:start_dissolve({G.C.GOLD})
        end
        delay(0.3)

        inc_career_stat('c_cards_sold', 1)
        if self.ability.set == 'Joker' then 
            inc_career_stat('c_jokers_sold', 1)
        end
        if self.ability.set == 'Joker' and G.GAME.blind and G.GAME.blind.name == 'Verdant Leaf' then 
            G.E_MANAGER:add_event(Event({trigger = 'immediate',func = function()
                G.GAME.blind:disable()
                return true
            end}))
        end
        G.E_MANAGER:add_event(Event({trigger = 'after',delay = 0.3, blocking = false,
        func = function()
            G.E_MANAGER:add_event(Event({trigger = 'immediate',
            func = function()
                G.E_MANAGER:add_event(Event({trigger = 'immediate',
                func = function()
                    G.CONTROLLER.locks.selling_card = nil
                    G.CONTROLLER:recall_cardarea_focus(area == G.jokers and 'jokers' or 'consumeables')
                return true
                end}))
            return true
            end}))
        return true
        end}))
        return true
    end}))
end

function Card:can_sell_card(context)
    if (G.play and #G.play.cards > 0) or
        (G.CONTROLLER.locked) or 
        (G.GAME.STOP_USE and G.GAME.STOP_USE > 0) --or 
        --G.STATE == G.STATES.BLIND_SELECT 
        then return false end
    if (G.SETTINGS.tutorial_complete or G.GAME.pseudorandom.seed ~= 'TUTORIAL' or G.GAME.round_resets.ante > 1) and
        self.area and
        self.area.config.type == 'joker' and
        not self.ability.eternal then
        return true
    end
    return false
end

function Card:calculate_dollar_bonus()
    if not self:can_calculate() then return end
    local obj = self.config.center
    if obj.calc_dollar_bonus and type(obj.calc_dollar_bonus) == 'function' then
        return obj:calc_dollar_bonus(self)
    end
    if self.ability.set == "Joker" then
        if self.ability.name == 'Golden Joker' then
            return self.ability.extra
        end
        if self.ability.name == 'Cloud 9' and self.ability.nine_tally and self.ability.nine_tally > 0 then
            return self.ability.extra*(self.ability.nine_tally)
        end
        if self.ability.name == 'Rocket' then
            return self.ability.extra.dollars
        end
        if self.ability.name == 'Satellite' then 
            local planets_used = 0
            for k, v in pairs(G.GAME.consumeable_usage) do
                if v.set == 'Planet' then planets_used = planets_used + 1 end
            end
            if planets_used == 0 then return end
            return self.ability.extra*planets_used
        end
        if self.ability.name == 'Delayed Gratification' and G.GAME.current_round.discards_used == 0 and G.GAME.current_round.discards_left > 0 then
            return G.GAME.current_round.discards_left*self.ability.extra
        end
    end
end

function Card:open()
    if self.ability.set == "Booster" then
        stop_use()
        G.STATE_COMPLETE = false 
        self.opening = true

        if not self.config.center.discovered then
            discover_card(self.config.center)
        end
        self.states.hover.can = false

        booster_obj = self.config.center
        if booster_obj and SMODS.Centers[booster_obj.key] then
            G.STATE = G.STATES.SMODS_BOOSTER_OPENED
            SMODS.OPENED_BOOSTER = self
        end
        G.GAME.pack_choices = self.ability.choose or self.config.center.config.choose or 1
        G.GAME.pack_choices = ((self.ability.choose and self.ability.extra) and math.min(math.floor(self.ability.extra), self.ability.choose)) or 1
        if G.GAME.modifiers.cry_misprint_min then
            G.GAME.pack_size = self.ability.extra
            if G.GAME.pack_size < 1 then G.GAME.pack_size = 1 end
            self.ability.extra = G.GAME.pack_size
            G.GAME.pack_choices = math.min(math.floor(G.GAME.pack_size), self.ability.choose)
            --G.GAME.pack_choices = math.min(math.floor(G.GAME.pack_size),cry_format(G.GAME.pack_choices * Cryptid.log_random(pseudoseed('cry_misprint_p'..G.GAME.round_resets.ante),G.GAME.modifiers.cry_misprint_min,G.GAME.modifiers.cry_misprint_max),"%.2f"))
        end
        if G.GAME.cry_oboe then
            self.ability.extra = self.ability.extra + G.GAME.cry_oboe
            G.GAME.pack_choices = G.GAME.pack_choices + G.GAME.cry_oboe
            G.GAME.cry_oboe = nil
        end
        if G.GAME.boostertag and G.GAME.boostertag > 0 then
            self.ability.extra = self.ability.extra * 2
            G.GAME.pack_choices = G.GAME.pack_choices * 2
            G.GAME.boostertag = math.max(0, G.GAME.boostertag - 1)
        end
        self.ability.extra = math.min(self.ability.extra, 1000)
        G.GAME.pack_choices = math.min(G.GAME.pack_choices, 1000)
        G.GAME.pack_size = self.ability.extra

        if self.cost > 0 then 
            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.2, func = function()
                inc_career_stat('c_shop_dollars_spent', self.cost)
                self:juice_up()
            return true end }))
            ease_dollars(-self.cost) 
       else
           delay(0.2)
       end

        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
            self:explode()
            local pack_cards = {}

            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 1.3*math.sqrt(G.SETTINGS.GAMESPEED), blockable = false, blocking = false, func = function()
                local _size = self.ability.extra
                
                for i = 1, _size do
                    local card = nil
                    if booster_obj.create_card and type(booster_obj.create_card) == "function" then
                        local _card_to_spawn = booster_obj:create_card(self, i)
                        if type((_card_to_spawn or {}).is) == 'function' and _card_to_spawn:is(Card) then
                            card = _card_to_spawn
                        else
                            card = SMODS.create_card(_card_to_spawn)
                        end
                    elseif self.ability.name:find('Arcana') then
                        if G.GAME.used_vouchers.v_omen_globe and pseudorandom('omen_globe') > 0.8 then
                            card = create_card("Spectral", G.pack_cards, nil, nil, true, true, nil, 'ar2')
                        else
                            card = create_card("Tarot", G.pack_cards, nil, nil, true, true, nil, 'ar1')
                        end
                    elseif self.ability.name:find('Celestial') then
                        if G.GAME.used_vouchers.v_telescope and i == 1 then
                            local _planet, _hand, _tally = nil, nil, 0
                            for k, v in ipairs(G.handlist) do
                                if G.GAME.hands[v].visible and G.GAME.hands[v].played > _tally then
                                    _hand = v
                                    _tally = G.GAME.hands[v].played
                                end
                            end
                            if _hand then
                                for k, v in pairs(G.P_CENTER_POOLS.Planet) do
                                    if v.config.hand_type == _hand then
                                        _planet = v.key
                                    end
                                end
                            end
                            card = create_card("Planet", G.pack_cards, nil, nil, true, true, _planet, 'pl1')
                        else
                            if G.GAME.used_vouchers.v_cry_satellite_uplink and pseudorandom('cry_satellite_uplink') > 0.8 then
                                card = create_card("Code", G.pack_cards, nil, nil, true, true, nil, 'pl2')
                            else
                                card = create_card("Planet", G.pack_cards, nil, nil, true, true, nil, 'pl1')
                            end
                        end
                    elseif self.ability.name:find('Spectral') then
                        card = create_card("Spectral", G.pack_cards, nil, nil, true, true, nil, 'spe')
                    elseif self.ability.name:find('Standard') then
                        card = create_card((pseudorandom(pseudoseed('stdset'..G.GAME.round_resets.ante)) > 0.6) and "Enhanced" or "Base", G.pack_cards, nil, nil, nil, true, nil, 'sta')
                        local edition_rate = 2
                        local edition = poll_edition('standard_edition'..G.GAME.round_resets.ante, edition_rate, true)
                        card:set_edition(edition)
                        card:set_seal(SMODS.poll_seal({mod = 10}))
                    elseif self.ability.name:find('Buffoon') then
                        card = create_card("Joker", G.pack_cards, nil, nil, true, true, nil, 'buf')

                    end
                    local edi = self.edition or {}
                    if edi.type then
                    	if card.ability.name ~= "cry-meteor"
                     	and card.ability.name ~= "cry-exoplanet"
                      	and card.ability.name ~= "cry-stardust" then
                    		card:set_edition({[edi.type] = true})
                      	end
                    end
                    local stickers = {'eternal', 'perishable', 'rental', 'banana'}
                    for _, v in ipairs(stickers) do
                    	if self.ability[v] then
                    		card.ability[v] = self.ability[v]
                    	end
                    end
                    card.T.x = self.T.x
                    card.T.y = self.T.y
                    card:start_materialize({G.C.WHITE, G.C.WHITE}, nil, 1.5*G.SETTINGS.GAMESPEED)
                    pack_cards[i] = card
                end
                return true
            end}))

            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 1.3*math.sqrt(G.SETTINGS.GAMESPEED), blockable = false, blocking = false, func = function()
                if G.pack_cards then 
                    if G.pack_cards and G.pack_cards.VT.y < G.ROOM.T.h then 
                    for k, v in ipairs(pack_cards) do
                        G.pack_cards:emplace(v)
                    end
                    return true
                    end
                end
            end}))

            SMODS.calculate_context({open_booster = true, card = self})

            if G.GAME.modifiers.inflation then 
                G.GAME.inflation = G.GAME.inflation + 1
                G.E_MANAGER:add_event(Event({func = function()
                  for k, v in pairs(G.I.CARD) do
                      if v.set_cost then v:set_cost() end
                  end
                  return true end }))
            end

        return true end }))
    end
end

function Card:redeem()
    if self.ability.set == "Voucher" then
        stop_use()
        if not self.config.center.discovered then
            discover_card(self.config.center)
        end
        if self.shop_voucher then G.GAME.current_round.voucher.spawn[self.config.center_key] = false end 
        if self.from_tag then G.GAME.current_round.voucher.spawn[G.GAME.current_round.voucher[1]] = false end

        self.states.hover.can = false
        G.GAME.used_vouchers[self.config.center_key] = true
        local top_dynatext = nil
        local bot_dynatext = nil
        
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.4, func = function()
                top_dynatext = DynaText({string = localize{type = 'name_text', set = self.config.center.set, key = self.config.center.key}, colours = {G.C.WHITE}, rotate = 1,shadow = true, bump = true,float=true, scale = 0.9, pop_in = 0.6/G.SPEEDFACTOR, pop_in_rate = 1.5*G.SPEEDFACTOR})
                bot_dynatext = DynaText({string = localize('k_redeemed_ex'), colours = {G.C.WHITE}, rotate = 2,shadow = true, bump = true,float=true, scale = 0.9, pop_in = 1.4/G.SPEEDFACTOR, pop_in_rate = 1.5*G.SPEEDFACTOR, pitch_shift = 0.25})
                self:juice_up(0.3, 0.5)
                play_sound('card1')
                play_sound('coin1')
                self.children.top_disp = UIBox{
                    definition =    {n=G.UIT.ROOT, config = {align = 'tm', r = 0.15, colour = G.C.CLEAR, padding = 0.15}, nodes={
                                        {n=G.UIT.O, config={object = top_dynatext}}
                                    }},
                    config = {align="tm", offset = {x=0,y=0},parent = self}
                }
                self.children.bot_disp = UIBox{
                        definition =    {n=G.UIT.ROOT, config = {align = 'tm', r = 0.15, colour = G.C.CLEAR, padding = 0.15}, nodes={
                                            {n=G.UIT.O, config={object = bot_dynatext}}
                                        }},
                        config = {align="bm", offset = {x=0,y=0},parent = self}
                    }
            return true end }))
        if self.cost ~= 0 then
            ease_dollars(-self.cost)
            inc_career_stat('c_shop_dollars_spent', self.cost)
        end
        inc_career_stat('c_vouchers_bought', 1)
        set_voucher_usage(self)
        check_for_unlock({type = 'run_redeem'})
        --G.GAME.current_round.voucher = nil

        G.GAME.current_round.cry_voucher_edition = nil
        G.GAME.current_round.cry_voucher_stickers = {eternal = false, perishable = false, rental = false, pinned = false, banana = false}
        self:apply_to_run()

        delay(0.6)
        SMODS.calculate_context({buying_card = true, card = self})
        if G.GAME.modifiers.inflation then 
            G.GAME.inflation = G.GAME.inflation + 1
            G.E_MANAGER:add_event(Event({func = function()
              for k, v in pairs(G.I.CARD) do
                  if v.set_cost then v:set_cost() end
              end
              return true end }))
        end
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 2.6, func = function()
            top_dynatext:pop_out(4)
            bot_dynatext:pop_out(4)
            return true end }))
        
        G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.5, func = function()
            self.children.top_disp:remove()
            self.children.top_disp = nil
            self.children.bot_disp:remove()
            self.children.bot_disp = nil
        return true end }))
    end
end

function Card:apply_to_run(center)
if (self and self.ability and self.ability.extra_disp) then	-- redeeming through centers isn't misprinted
	local self_disp = self.ability.extra_disp
	local orig_disp = self.config.center.config.extra_disp
	local self_extra = self.ability.extra
	local orig_extra = self.config.center.config.extra

	local new_fac = self_disp / orig_disp
	self.ability.extra = new_fac*orig_extra
end
    local card_to_save = self and copy_card(self) or Card(0, 0, G.CARD_W, G.CARD_H, G.P_CARDS.empty, center)
    card_to_save.VT.x, card_to_save.VT.y = G.vouchers.T.x, G.vouchers.T.y
    card_to_save.ability.extra = self and self.ability.extra or card_to_save.ability.extra
    G.vouchers:emplace(card_to_save)
    SMODS.enh_cache:clear()
    local center_table = {
        name = center and center.name or self and self.ability.name,
        extra = center and center.config.extra or self and self.ability.extra
    }
    local obj = center or self.config.center
    if obj.redeem and type(obj.redeem) == 'function' then
        obj:redeem(card_to_save)
        return
    end    if center_table.name == 'Overstock' or center_table.name == 'Overstock Plus' then
        G.E_MANAGER:add_event(Event({func = function()
            change_shop_size(center_table.extra)
            return true end }))
    end
    if center_table.name == 'Tarot Merchant' or center_table.name == 'Tarot Tycoon' then
        G.E_MANAGER:add_event(Event({func = function()
            G.GAME.tarot_rate = G.GAME.tarot_rate*center_table.extra
            return true end }))
    end
    if center_table.name == 'Planet Merchant' or center_table.name == 'Planet Tycoon' then
        G.E_MANAGER:add_event(Event({func = function()
            G.GAME.planet_rate = G.GAME.planet_rate*center_table.extra
            return true end }))
    end
    if center_table.name == 'Hone' or center_table.name == 'Glow Up' then
        G.E_MANAGER:add_event(Event({func = function()
            G.GAME.edition_rate = center_table.extra
            return true end }))
    end
    if center_table.name == 'Magic Trick' or center_table.name == 'Illusion' then
        G.E_MANAGER:add_event(Event({func = function()
            G.GAME.playing_card_rate = center_table.extra
            return true end }))
    end
    if center_table.name == 'Telescope' or center_table.name == 'Observatory' then
    end
        if center_table.name == 'Crystal Ball' then
        G.E_MANAGER:add_event(Event({func = function()
            G.consumeables.config.card_limit = G.consumeables.config.card_limit + center_table.extra
            return true end }))
    end

    if center_table.name == 'Clearance Sale' or center_table.name == 'Liquidation' then
        G.E_MANAGER:add_event(Event({func = function()
            G.GAME.discount_percent = center_table.extra
            for k, v in pairs(G.I.CARD) do
                if v.set_cost then v:set_cost() end
            end
            return true end }))
    end
    if center_table.name == 'Reroll Surplus' or center_table.name == 'Reroll Glut' then
        G.E_MANAGER:add_event(Event({func = function()
            G.GAME.round_resets.reroll_cost = G.GAME.round_resets.reroll_cost - center_table.extra
            G.GAME.current_round.reroll_cost = math.max(0, G.GAME.current_round.reroll_cost - center_table.extra)
            return true end }))
    end
    if center_table.name == 'Seed Money' or center_table.name == 'Money Tree' then
        G.E_MANAGER:add_event(Event({func = function()
            G.GAME.interest_cap = center_table.extra
            return true end }))
    end
    if center_table.name == 'Grabber' or center_table.name == 'Nacho Tong' then
        G.GAME.round_resets.hands = G.GAME.round_resets.hands + center_table.extra
        ease_hands_played(center_table.extra)
    end
    if center_table.name == 'Paint Brush' or center_table.name == 'Palette' then
        G.hand:change_size(center_table.extra)
    end
    if center_table.name == 'Wasteful' or center_table.name == 'Recyclomancy' then
        G.GAME.round_resets.discards = G.GAME.round_resets.discards + center_table.extra
        ease_discard(center_table.extra)
    end
    if center_table.name == 'Blank' then
        check_for_unlock({type = 'blank_redeems'})
    end
        if center_table.name == 'Antimatter' then
        G.E_MANAGER:add_event(Event({func = function()
            if G.jokers then
                G.jokers.config.card_limit = G.jokers.config.card_limit + center_table.extra
            end
            return true end }))
    end

    if center_table.name == 'Hieroglyph' or center_table.name == 'Petroglyph' then
        ease_ante(math.floor(-center_table.extra))
        G.GAME.round_resets.blind_ante = G.GAME.round_resets.blind_ante or G.GAME.round_resets.ante
        G.GAME.round_resets.blind_ante = G.GAME.round_resets.blind_ante-center_table.extra

        if center_table.name == 'Hieroglyph' then
            G.GAME.round_resets.hands = G.GAME.round_resets.hands - center_table.extra
            ease_hands_played(-center_table.extra)
        end
        if center_table.name == 'Petroglyph' then
            G.GAME.round_resets.discards = G.GAME.round_resets.discards - center_table.extra
            ease_discard(-center_table.extra)
        end
    end
end

function Card:explode(dissolve_colours, explode_time_fac)
    local explode_time = 1.3*(explode_time_fac or 1)*(math.sqrt(G.SETTINGS.GAMESPEED))
    self.dissolve = 0
    self.dissolve_colours = dissolve_colours
        or {G.C.WHITE}

    local start_time = G.TIMERS.TOTAL
    local percent = 0
    play_sound('explosion_buildup1')
    self.juice = {
        scale = 0,
        r = 0,
        handled_elsewhere = true,
        start_time = start_time, 
        end_time = start_time + explode_time
    }

    local childParts1 = Particles(0, 0, 0,0, {
        timer_type = 'TOTAL',
        timer = 0.01*explode_time,
        scale = 0.2,
        speed = 2,
        lifespan = 0.2*explode_time,
        attach = self,
        colours = self.dissolve_colours,
        fill = true
    })
    local childParts2 = nil

    G.E_MANAGER:add_event(Event({
        blockable = false,
        func = (function()
                if self.juice then 
                    percent = (G.TIMERS.TOTAL - start_time)/explode_time
                    self.juice.r = 0.05*(math.sin(5*G.TIMERS.TOTAL) + math.cos(0.33 + 41.15332*G.TIMERS.TOTAL) + math.cos(67.12*G.TIMERS.TOTAL))*percent
                    self.juice.scale = percent*0.15
                end
                if G.TIMERS.TOTAL - start_time > 1.5*explode_time then return true end
            end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'ease',
        blockable = false,
        ref_table = self,
        ref_value = 'dissolve',
        ease_to = 0.3,
        delay =  0.9*explode_time,
        func = (function(t) return t end)
    }))

    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  0.9*explode_time,
        func = (function()
            childParts2 = Particles(0, 0, 0,0, {
                timer_type = 'TOTAL',
                pulse_max = 30,
                timer = 0.003,
                scale = 0.6,
                speed = 15,
                lifespan = 0.5,
                attach = self,
                colours = self.dissolve_colours,
            })
            childParts2:set_role({r_bond = 'Weak'})
            G.E_MANAGER:add_event(Event({
                trigger = 'ease',
                blockable = false,
                ref_table = self,
                ref_value = 'dissolve',
                ease_to = 1,
                delay =  0.1*explode_time,
                func = (function(t) return t end)
            }))
            self:juice_up()
            G.VIBRATION = G.VIBRATION + 1
            play_sound('explosion_release1')
            childParts1:fade(0.3*explode_time) return true end)
    }))

    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  1.4*explode_time,
        func = (function()
            G.E_MANAGER:add_event(Event({
                trigger = 'ease',
                blockable = false, 
                blocking = false,
                ref_value = 'scale',
                ref_table = childParts2,
                ease_to = 0,
                delay = 0.1*explode_time
            }))
            return true end)
    }))

    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  1.5*explode_time,
        func = (function() self:remove() return true end)
    }))
end

function Card:shatter()
    local dissolve_time = 0.7
    self.shattered = true
    self.dissolve = 0
    self.dissolve_colours = {{1,1,1,0.8}}
    self:juice_up()
    local childParts = Particles(0, 0, 0,0, {
        timer_type = 'TOTAL',
        timer = 0.007*dissolve_time,
        scale = 0.3,
        speed = 4,
        lifespan = 0.5*dissolve_time,
        attach = self,
        colours = self.dissolve_colours,
        fill = true
    })
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  0.5*dissolve_time,
        func = (function() childParts:fade(0.15*dissolve_time) return true end)
    }))
    G.E_MANAGER:add_event(Event({
        blockable = false,
        func = (function()
                play_sound('glass'..math.random(1, 6), math.random()*0.2 + 0.9,0.5)
                play_sound('generic1', math.random()*0.2 + 0.9,0.5)
            return true end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'ease',
        blockable = false,
        ref_table = self,
        ref_value = 'dissolve',
        ease_to = 1,
        delay =  0.5*dissolve_time,
        func = (function(t) return t end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  0.55*dissolve_time,
        func = (function() self:remove() return true end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  0.51*dissolve_time,
    }))
end

function Card:start_dissolve(dissolve_colours, silent, dissolve_time_fac, no_juice)
    local dissolve_time = 0.7*(dissolve_time_fac or 1)
    self.dissolve = 0
    self.dissolve_colours = dissolve_colours
        or {G.C.BLACK, G.C.ORANGE, G.C.RED, G.C.GOLD, G.C.JOKER_GREY}
    if not no_juice then self:juice_up() end
    local childParts = Particles(0, 0, 0,0, {
        timer_type = 'TOTAL',
        timer = 0.01*dissolve_time,
        scale = 0.1,
        speed = 2,
        lifespan = 0.7*dissolve_time,
        attach = self,
        colours = self.dissolve_colours,
        fill = true
    })
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  0.7*dissolve_time,
        func = (function() childParts:fade(0.3*dissolve_time) return true end)
    }))
    if not silent then 
        G.E_MANAGER:add_event(Event({
            blockable = false,
            func = (function()
                    play_sound('whoosh2', math.random()*0.2 + 0.9,0.5)
                    play_sound('crumple'..math.random(1, 5), math.random()*0.2 + 0.9,0.5)
                return true end)
        }))
    end
    G.E_MANAGER:add_event(Event({
        trigger = 'ease',
        blockable = false,
        ref_table = self,
        ref_value = 'dissolve',
        ease_to = 1,
        delay =  1*dissolve_time,
        func = (function(t) return t end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  1.05*dissolve_time,
        func = (function() self:remove() return true end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  1.051*dissolve_time,
    }))
end

function Card:start_materialize(dissolve_colours, silent, timefac)
    local dissolve_time = 0.6*(timefac or 1)
    self.states.visible = true
    self.states.hover.can = false
    self.dissolve = 1
    self.dissolve_colours = dissolve_colours or
    (self.ability.set == 'Joker' and {G.C.RARITY[self.config.center.rarity]}) or
    (self.ability.set == 'Planet'  and {G.C.SECONDARY_SET.Planet}) or
    (self.ability.set == 'Tarot' and {G.C.SECONDARY_SET.Tarot}) or
    (self.ability.set == 'Spectral' and {G.C.SECONDARY_SET.Spectral}) or
    (self.ability.set == 'Booster' and {G.C.BOOSTER}) or
    (self.ability.set == 'Voucher' and {G.C.SECONDARY_SET.Voucher, G.C.CLEAR}) or 
    {G.C.GREEN}
    self:juice_up()
    self.children.particles = Particles(0, 0, 0,0, {
        timer_type = 'TOTAL',
        timer = 0.025*dissolve_time,
        scale = 0.25,
        speed = 3,
        lifespan = 0.7*dissolve_time,
        attach = self,
        colours = self.dissolve_colours,
        fill = true
    })
    if not silent then 
        if not G.last_materialized or G.last_materialized +0.01 < G.TIMERS.REAL or G.last_materialized > G.TIMERS.REAL then
            G.last_materialized = G.TIMERS.REAL
            G.E_MANAGER:add_event(Event({
                blockable = false,
                func = (function()
                        play_sound('whoosh1', math.random()*0.1 + 0.6,0.3)
                        play_sound('crumple'..math.random(1,5), math.random()*0.2 + 1.2,0.8)
                    return true end)
            }))
        end
    end
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  0.5*dissolve_time,
        func = (function() if self.children.particles then self.children.particles.max = 0 end return true end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'ease',
        blockable = false,
        ref_table = self,
        ref_value = 'dissolve',
        ease_to = 0,
        delay =  1*dissolve_time,
        func = (function(t) return t end)
    }))
    G.E_MANAGER:add_event(Event({
        trigger = 'after',
        blockable = false,
        delay =  1.05*dissolve_time,
        func = (function() self.states.hover.can = true; if self.children.particles then self.children.particles:remove(); self.children.particles = nil end return true end)
    }))
end

function Card:calculate_seal(context)
    
    local obj = G.P_SEALS[self.seal] or {}
    if obj.calculate and type(obj.calculate) == 'function' then
    	local o = obj:calculate(self, context)
    	if o then
            if not o.card then o.card = self end
            return o
        end
    end
    if context.repetition then
        if self.seal == 'Red' then
                return {
                    message = localize('k_again_ex'),
                    repetitions = 1,
                    card = self
                }
        end
    end
    if context.discard and context.other_card == self then
        if self.seal == 'Purple' and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
            G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
            G.E_MANAGER:add_event(Event({
                trigger = 'before',
                delay = 0.0,
                func = (function()
                        local card = create_card('Tarot',G.consumeables, nil, nil, nil, nil, nil, '8ba')
                        card:add_to_deck()
                        G.consumeables:emplace(card)
                        G.GAME.consumeable_buffer = 0
                    return true
                end)}))
            card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize('k_plus_tarot'), colour = G.C.PURPLE})
            return nil, true
        end
    end
end

function Card:calculate_rental()
    if self.ability.rental then
        ease_dollars(-G.GAME.rental_rate)
        card_eval_status_text(self, 'dollars', -G.GAME.rental_rate)
    end
end

function Card:calculate_perishable()
    if self.ability.perishable and not self.ability.perish_tally then self.ability.perish_tally = G.GAME.perishable_rounds end
    if self.ability.perishable and self.ability.perish_tally > 0 then
        if self.ability.perish_tally == 1 then
            self.ability.perish_tally = 0
            card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize('k_disabled_ex'),colour = G.C.FILTER, delay = 0.45})
            self:set_debuff()
        else
            self.ability.perish_tally = self.ability.perish_tally - 1
            card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type='variable',key='a_remaining',vars={self.ability.perish_tally}},colour = G.C.FILTER, delay = 0.45})
        end
    end
end

function Card:calculate_joker(context)
    local obj = self.config.center
    if self.ability.set ~= "Enhanced" and obj.calculate and type(obj.calculate) == 'function' then
        local o, t = obj:calculate(self, context)
        if o or t then return o, t end
    end

    if self.ability.set == "Joker" then
        if self.ability.name == "Blueprint" then
            local other_joker = nil
            for i = 1, #G.jokers.cards do
                if G.jokers.cards[i] == self then other_joker = G.jokers.cards[i+1] end
            end
            if other_joker and other_joker ~= self and not context.no_blueprint then
                context.blueprint = (context.blueprint and (context.blueprint + 1)) or 1
                context.blueprint_card = context.blueprint_card or self
                if context.blueprint > #G.jokers.cards + 1 then return end
                local other_joker_ret = other_joker:calculate_joker(context)
                context.blueprint = nil
                local eff_card = context.blueprint_card or self
                context.blueprint_card = nil
                if other_joker_ret then 
                    other_joker_ret.card = eff_card
                    other_joker_ret.colour = G.C.BLUE
                    return other_joker_ret
                end
            end
        end
        if self.ability.name == "Brainstorm" then
            local other_joker = G.jokers.cards[1]
            if other_joker and other_joker ~= self and not context.no_blueprint then
                context.blueprint = (context.blueprint and (context.blueprint + 1)) or 1
                context.blueprint_card = context.blueprint_card or self
                if context.blueprint > #G.jokers.cards + 1 then return end
                local other_joker_ret = other_joker:calculate_joker(context)
                context.blueprint = nil
                local eff_card = context.blueprint_card or self
                context.blueprint_card = nil
                if other_joker_ret then 
                    other_joker_ret.card = eff_card
                    other_joker_ret.colour = G.C.RED
                    return other_joker_ret
                end
            end
        end
        if context.open_booster then
            if self.ability.name == 'Hallucination' and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
                if pseudorandom('halu'..G.GAME.round_resets.ante) < cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged)/self.ability.extra then
                    G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
                    G.E_MANAGER:add_event(Event({
                        trigger = 'before',
                        delay = 0.0,
                        func = (function()
                                local card = create_card('Tarot',G.consumeables, nil, nil, nil, nil, nil, 'hal')
                                card:add_to_deck()
                                G.consumeables:emplace(card)
                                G.GAME.consumeable_buffer = 0
                            return true
                        end)}))
                    card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize('k_plus_tarot'), colour = G.C.PURPLE})
                    return nil, true
                end
            end
        elseif context.buying_card then
            
        elseif context.selling_self then
            if self.ability.name == 'Luchador' then
                if G.GAME.blind and ((not G.GAME.blind.disabled) and (G.GAME.blind:get_type() == 'Boss')) then 
                    card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('ph_boss_disabled')})
                   G.GAME.blind:disable()
                    return nil, true
                end
            end
            if self.ability.name == 'Diet Cola' then
                G.E_MANAGER:add_event(Event({
                    func = (function()
                        add_tag(Tag('tag_double'))
                        play_sound('generic1', 0.9 + math.random()*0.1, 0.8)
                        play_sound('holo1', 1.2 + math.random()*0.1, 0.4)
                       return true
                   end)
                }))
                return nil, true
            end
            if self.ability.name == 'Invisible Joker' and (self.ability.invis_rounds >= self.ability.extra) and not context.blueprint then
                local eval = function(card) return (card.ability.loyalty_remaining == 0) and not G.RESET_JIGGLES end
                                    juice_card_until(self, eval, true)
                local jokers = {}
                for i=1, #G.jokers.cards do 
                    if G.jokers.cards[i] ~= self then
                        jokers[#jokers+1] = G.jokers.cards[i]
                    end
                end
                if #jokers > 0 then 
                    if #G.jokers.cards <= G.jokers.config.card_limit then 
                        card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_duplicated_ex')})
                        local chosen_joker = pseudorandom_element(jokers, pseudoseed('invisible'))
                        local card = copy_card(chosen_joker, nil, nil, nil, chosen_joker.edition and chosen_joker.edition.negative)
                        if card.ability.invis_rounds then card.ability.invis_rounds = 0 end
                        card:add_to_deck()
                        G.jokers:emplace(card)                        return nil, true
                    else
                        card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_no_room_ex')})
                    end
                else
                    card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_no_other_jokers')})
                end
            end
        elseif context.selling_card then
                if self.ability.name == 'Campfire' and not context.blueprint then
                    self.ability.x_mult = self.ability.x_mult + self.ability.extra
                    G.E_MANAGER:add_event(Event({
                        func = function() card_eval_status_text(self, 'extra', nil, nil, nil, {message =             localize('k_upgrade_ex')}); return true
               end}))
            end
            if self.ability.name == 'Campfire' and not context.blueprint then return nil, true end
        elseif context.reroll_shop then
            if self.ability.name == 'Flash Card' and not context.blueprint then
                self.ability.mult = self.ability.mult + self.ability.extra
                G.E_MANAGER:add_event(Event({
                    func = (function()
                        card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_mult', vars = {self.ability.mult}}, colour =            G.C.MULT})
                   return true
               end)}))
            end
            if self.ability.name == 'Flash Card' and not context.blueprint then return nil, true end
        elseif context.ending_shop then
            if self.ability.name == 'Perkeo' then
                local eligibleJokers = {}
                for i = 1, #G.consumeables.cards do
                    if G.consumeables.cards[i].ability.consumeable then
                        eligibleJokers[#eligibleJokers + 1] = G.consumeables.cards[i]
                    end
                end
                if #eligibleJokers > 0 then
                    G.E_MANAGER:add_event(Event({
                        func = function() 
                            local card = copy_card(pseudorandom_element(eligibleJokers, pseudoseed('perkeo')), nil)
                            card:set_edition({negative = true}, true)
                            card:add_to_deck()
                            G.consumeables:emplace(card) 
                            return true
                        end}))
                    card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_duplicated_ex')})
                    return nil, true
                end
                return
            end
            return
        elseif context.skip_blind then
            if self.ability.name == 'Throwback' and not context.blueprint then
                G.E_MANAGER:add_event(Event({
                    func = function() 
                        card_eval_status_text(self, 'extra', nil, nil, nil, {
                            message = localize{type = 'variable', key = 'a_xmult', vars = {self.ability.x_mult}},
                                colour = G.C.RED,
                            card = self
                        }) 
                        return true
                    end}))
        return nil, true            end
            return
        elseif context.skipping_booster then
            if self.ability.name == 'Red Card' and not context.blueprint then
                self.ability.mult = self.ability.mult + self.ability.extra
                                G.E_MANAGER:add_event(Event({
                    func = function() 
                        card_eval_status_text(self, 'extra', nil, nil, nil, {
                            message = localize{type = 'variable', key = 'a_mult', vars = {self.ability.extra}},
                            colour = G.C.RED,
                            delay = 0.45, 
                            card = self
                        }) 
                        return true
                    end}))
        return nil, true            end
            return
        elseif context.playing_card_added and not self.getting_sliced then
            if self.ability.name == 'Hologram' and (not context.blueprint)
                and context.cards and context.cards[1] then
                    self.ability.x_mult = self.ability.x_mult + #context.cards*self.ability.extra
                    card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_xmult', vars = {self.ability.x_mult}}})
        return nil, true            end
        elseif context.first_hand_drawn then
            if self.ability.name == 'Certificate' then
                local _card = create_playing_card({
                    front = pseudorandom_element(G.P_CARDS, pseudoseed('cert_fr')),
                    center = G.P_CENTERS.c_base}, G.discard, true, nil, {G.C.SECONDARY_SET.Enhanced}, true)
                _card:set_seal(SMODS.poll_seal({guaranteed = true, type_key = 'certsl'}))
                G.E_MANAGER:add_event(Event({
                    func = function()
                        G.hand:emplace(_card)
                        _card:start_materialize()
                        G.GAME.blind:debuff_card(_card)
                        G.hand:sort()
                        if context.blueprint_card then context.blueprint_card:juice_up() else self:juice_up() end
                        return true
                    end}))
                playing_card_joker_effects({_card})
                
            return nil, true            end
            if self.ability.name == 'DNA' and not context.blueprint then
                local eval = function() return G.GAME.current_round.hands_played == 0 end
                juice_card_until(self, eval, true)
            end
            if self.ability.name == 'Trading Card' and not context.blueprint then
                local eval = function() return G.GAME.current_round.discards_used == 0 and not G.RESET_JIGGLES end
                juice_card_until(self, eval, true)
            end
        elseif context.setting_blind and not self.getting_sliced then
            if self.ability.name == 'Chicot' and not context.blueprint
            and context.blind.boss and not self.getting_sliced then
                G.E_MANAGER:add_event(Event({func = function()
                    G.E_MANAGER:add_event(Event({func = function()
                        G.GAME.blind:disable()
                        play_sound('timpani')
                        delay(0.4)
                        return true end }))
                    card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize('ph_boss_disabled')})
                return true end }))
            return nil, true            end
            if self.ability.name == 'Madness' and not context.blueprint and not context.blind.boss then
                self.ability.x_mult = self.ability.x_mult + self.ability.extra
                local destructable_jokers = {}
                for i = 1, #G.jokers.cards do
                    if G.jokers.cards[i] ~= self and not G.jokers.cards[i].ability.eternal and not G.jokers.cards[i].getting_sliced then destructable_jokers[#destructable_jokers+1] = G.jokers.cards[i] end
                end
                local joker_to_destroy = #destructable_jokers > 0 and pseudorandom_element(destructable_jokers, pseudoseed('madness')) or nil

                if joker_to_destroy and not (context.blueprint_card or self).getting_sliced then 
                    joker_to_destroy.getting_sliced = true
                    G.E_MANAGER:add_event(Event({func = function()
                        (context.blueprint_card or self):juice_up(0.8, 0.8)
                        joker_to_destroy:start_dissolve({G.C.RED}, nil, 1.6)
                    return true end }))
                end
                if not (context.blueprint_card or self).getting_sliced then
                    card_eval_status_text((context.blueprint_card or self), 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_xmult', vars = {self.ability.x_mult}}})
                end
            return nil, true            end
            if self.ability.name == 'Burglar' and not (context.blueprint_card or self).getting_sliced then
                G.E_MANAGER:add_event(Event({func = function()
                    ease_discard(-G.GAME.current_round.discards_left, nil, true)
                    ease_hands_played(self.ability.extra)
                    card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_hands', vars = {self.ability.extra}}})
                return true end }))
            return nil, true            end
            if self.ability.name == 'Riff-raff' and not (context.blueprint_card or self).getting_sliced and #G.jokers.cards + G.GAME.joker_buffer < G.jokers.config.card_limit then
                local jokers_to_create = math.min(2, G.jokers.config.card_limit - (#G.jokers.cards + G.GAME.joker_buffer))
                G.GAME.joker_buffer = G.GAME.joker_buffer + jokers_to_create
                G.E_MANAGER:add_event(Event({
                    func = function() 
                        for i = 1, jokers_to_create do
                            local card = create_card('Joker', G.jokers, nil, 0, nil, nil, nil, 'rif')
                            card:add_to_deck()
                            G.jokers:emplace(card)
                            card:start_materialize()
                            G.GAME.joker_buffer = 0
                        end
                        return true
                    end}))   
                    card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_plus_joker'), colour = G.C.BLUE}) 
            return nil, true            end
            if self.ability.name == 'Cartomancer' and not (context.blueprint_card or self).getting_sliced and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
                G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
                G.E_MANAGER:add_event(Event({
                    func = (function()
                        G.E_MANAGER:add_event(Event({
                            func = function() 
                                local card = create_card('Tarot',G.consumeables, nil, nil, nil, nil, nil, 'car')
                                card:add_to_deck()
                                G.consumeables:emplace(card)
                                G.GAME.consumeable_buffer = 0
                                return true
                            end}))   
                            card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_plus_tarot'), colour = G.C.PURPLE})                       
                        return true
                    end)}))
            return nil, true            end
            if self.ability.name == 'Ceremonial Dagger' and not context.blueprint then
                local my_pos = nil
                for i = 1, #G.jokers.cards do
                    if G.jokers.cards[i] == self then my_pos = i; break end
                end
                if my_pos and G.jokers.cards[my_pos+1] and not self.getting_sliced and not G.jokers.cards[my_pos+1].ability.eternal and not G.jokers.cards[my_pos+1].getting_sliced then 
                    local sliced_card = G.jokers.cards[my_pos+1]
                    if sliced_card.config.center.rarity == "cry_exotic" then check_for_unlock({type = "what_have_you_done"}) end
                    sliced_card.getting_sliced = true
                    G.GAME.joker_buffer = G.GAME.joker_buffer - 1
                    G.E_MANAGER:add_event(Event({func = function()
                        G.GAME.joker_buffer = 0
                        self.ability.mult = self.ability.mult + sliced_card.sell_cost*2
                        self:juice_up(0.8, 0.8)
                        sliced_card:start_dissolve({HEX("57ecab")}, nil, 1.6)
                        play_sound('slice1', 0.96+math.random()*0.08)
                    return true end }))
                    card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_mult', vars = {self.ability.mult+2*sliced_card.sell_cost}}, colour = G.C.RED, no_juice = true})
            return nil, true                end
            end
            if self.ability.name == 'Marble Joker' and not (context.blueprint_card or self).getting_sliced  then
                local front = pseudorandom_element(G.P_CARDS, pseudoseed('marb_fr'))
                G.playing_card = (G.playing_card and G.playing_card + 1) or 1
                local card = Card(G.discard.T.x + G.discard.T.w/2, G.discard.T.y, G.CARD_W, G.CARD_H, front, G.P_CENTERS.m_stone, {playing_card = G.playing_card})
                G.E_MANAGER:add_event(Event({
                    func = function()
                        card:start_materialize({G.C.SECONDARY_SET.Enhanced})
                        G.play:emplace(card)
                        table.insert(G.playing_cards, card)
                        return true
                    end}))
                card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_plus_stone'), colour = G.C.SECONDARY_SET.Enhanced})
                
                G.E_MANAGER:add_event(Event({
                    func = function()
                        G.deck.config.card_limit = G.deck.config.card_limit + 1
                        return true
                    end}))
                    draw_card(G.play,G.deck, 90,'up', nil)
                
                playing_card_joker_effects({card})
        return nil, true            end
            return
        elseif context.destroying_card and not context.blueprint then
            if self.ability.name == 'Sixth Sense' and #context.full_hand == 1 and context.full_hand[1]:get_id() == 6 and not context.full_hand[1].ability.eternal and G.GAME.current_round.hands_played == 0 then
                if #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
                    G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
                    G.E_MANAGER:add_event(Event({
                        trigger = 'before',
                        delay = 0.0,
                        func = (function()
                                local card = create_card('Spectral',G.consumeables, nil, nil, nil, nil, nil, 'sixth')
                                card:add_to_deck()
                                G.consumeables:emplace(card)
                                G.GAME.consumeable_buffer = 0
                            return true
                        end)}))
                    card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_plus_spectral'), colour = G.C.SECONDARY_SET.Spectral})
                end
               return true
            end
            return nil
        elseif context.cards_destroyed then
            if self.ability.name == 'Caino' and not context.blueprint then
                local faces = 0
                for k, v in ipairs(context.glass_shattered) do
                    if v:is_face() then
                        faces = faces + 1
                    end
                end
                if faces > 0 then
                    G.E_MANAGER:add_event(Event({
                        func = function()
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            self.ability.caino_xmult = self.ability.caino_xmult + faces*self.ability.extra
                          return true
                        end
                      }))
                    card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_xmult', vars = {self.ability.caino_xmult + faces*self.ability.extra}}})
                    return true
                end
              }))
                end

                return
            end
            if self.ability.name == 'Glass Joker' and not context.blueprint then
                local glasses = 0
                for k, v in ipairs(context.glass_shattered) do
                    if v.shattered then
                        glasses = glasses + 1
                    end
                end
                if glasses > 0 then
                    G.E_MANAGER:add_event(Event({
                        func = function()
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            self.ability.x_mult = self.ability.x_mult + self.ability.extra*glasses
                          return true
                        end
                      }))
                    card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_xmult', vars = {self.ability.x_mult + self.ability.extra*glasses}}})
                    return true
                end
              }))
                end

                return
            end
            
        elseif context.remove_playing_cards then
            if self.ability.name == 'Caino' and not context.blueprint then
                local face_cards = 0
                for k, val in ipairs(context.removed) do
                    if val:is_face() then face_cards = face_cards + 1 end
                end
                if face_cards > 0 then
                    self.ability.caino_xmult = self.ability.caino_xmult + face_cards*self.ability.extra
                    G.E_MANAGER:add_event(Event({
                    func = function() card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_xmult', vars = {self.ability.caino_xmult}}}); return true
                    end}))                    return nil, true
                end
                return
            end

            if self.ability.name == 'Glass Joker' and not context.blueprint then
                local glass_cards = 0
                for k, val in ipairs(context.removed) do
                    if val.shattered then glass_cards = glass_cards + 1 end
                end
                if glass_cards > 0 then 
                    G.E_MANAGER:add_event(Event({
                        func = function()
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            self.ability.x_mult = self.ability.x_mult + self.ability.extra*glass_cards
                        return true
                        end
                    }))
                    card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type = 'variable', key = 'a_xmult', vars = {self.ability.x_mult + self.ability.extra*glass_cards}}})
                    return true
                        end
                    }))                    return nil, true
                end
                return
            end
        elseif context.using_consumeable then
            if self.ability.name == 'Glass Joker' and not context.blueprint and context.consumeable.ability.name == 'The Hanged Man'  then
                local shattered_glass = 0
                for k, val in ipairs(G.hand.highlighted) do
                    if SMODS.has_enhancement(val, 'm_glass') then shattered_glass = shattered_glass + 1 end
                end
                if shattered_glass > 0 then
                    self.ability.x_mult = self.ability.x_mult + self.ability.extra*shattered_glass
                    G.E_MANAGER:add_event(Event({
                        func = function() card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type='variable',key='a_xmult',vars={self.ability.x_mult}}}); return true
                        end}))
            return nil, true                end
                return
            end
            if self.ability.name == 'Fortune Teller' and not context.blueprint and (context.consumeable.ability.set == "Tarot") then
                G.E_MANAGER:add_event(Event({
                    func = function() card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type='variable',key='a_mult',vars={G.GAME.consumeable_usage_total.tarot}}}); return true
                    end}))
            return nil, true            end
            if self.ability.name == 'Constellation' and not context.blueprint and context.consumeable.ability.set == 'Planet' then
                self.ability.x_mult = self.ability.x_mult + self.ability.extra
                G.E_MANAGER:add_event(Event({
                    func = function() card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize{type='variable',key='a_xmult',vars={self.ability.x_mult}}}); return true
                    end}))
                return
        nil, true            end
            return
        elseif context.debuffed_hand then 
            if self.ability.name == 'Matador' then
                if G.GAME.blind.triggered then 
                    ease_dollars(self.ability.extra)
                    G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + self.ability.extra
                    if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
                    return {
                        message = localize('$')..self.ability.extra,
                        colour = G.C.MONEY
                    }
                end
            end
        elseif context.pre_discard then
            if self.ability.name == 'Burnt Joker' and G.GAME.current_round.discards_used <= 0 and not context.hook then
                local text,disp_text = G.FUNCS.get_poker_hand_info(G.hand.highlighted)
                card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('k_upgrade_ex')})
                update_hand_text({sound = 'button', volume = 0.7, pitch = 0.8, delay = 0.3}, {handname=localize(text, 'poker_hands'),chips = G.GAME.hands[text].chips, mult = G.GAME.hands[text].mult, level=G.GAME.hands[text].level})
                level_up_hand(context.blueprint_card or self, text, nil, 1)
                update_hand_text({sound = 'button', volume = 0.7, pitch = 1.1, delay = 0}, {mult = 0, chips = 0, handname = '', level = ''})
        return nil, true            end
        elseif context.discard then
            if self.ability.name == 'Ramen' and not context.blueprint then
                if self.ability.x_mult - self.ability.extra <= 1 then 
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            play_sound('tarot1')
                            self.T.r = -0.2
                            self:juice_up(0.3, 0.4)
                            self.states.drag.is = true
                            self.children.center.pinch.x = true
                            G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, blockable = false,
                                func = function()
                                        G.jokers:remove_card(self)
                                        self:remove()
                                        self = nil
                                    return true; end})) 
                            return true
                        end
                    })) 
                    return {
                        card = self,
                        message = localize('k_eaten_ex'),
                        colour = G.C.FILTER
                    }
                else
                    self.ability.x_mult = self.ability.x_mult - self.ability.extra
                    return {
                        delay = 0.2,
                        card = self,
                        message = localize{type='variable',key='a_xmult_minus',vars={self.ability.extra}},
                        colour = G.C.RED
                    }
                end
            end
            if self.ability.name == 'Yorick' and not context.blueprint then
                if self.ability.yorick_discards <= 1 then
                    self.ability.yorick_discards = self.ability.extra.discards
                    self.ability.x_mult = self.ability.x_mult + self.ability.extra.xmult
                    return {
                        card = self,
                        delay = 0.2,
                        message = localize{type='variable',key='a_xmult',vars={self.ability.x_mult}},
                        colour = G.C.RED
                    }
                else
                    self.ability.yorick_discards = self.ability.yorick_discards - 1
                    return nil, true
                end
                return
            end
            if self.ability.name == 'Trading Card' and not context.blueprint and 
            G.GAME.current_round.discards_used <= 0 and #context.full_hand == 1 and not context.other_card.ability.eternal then
                ease_dollars(self.ability.extra)
                return {
                    message = localize('$')..self.ability.extra,
                    colour = G.C.MONEY,
                    delay = 0.45, 
                    remove = true,
                    card = self
                }
            end
            
            if self.ability.name == 'Castle' and
            not context.other_card.debuff and
            context.other_card:is_suit(G.GAME.current_round.castle_card.suit) and not context.blueprint then
                self.ability.extra.chips = self.ability.extra.chips + self.ability.extra.chip_mod
                  
                return {
                    message = localize('k_upgrade_ex'),
                    card = self,
                    colour = G.C.CHIPS
                }
            end
            if self.ability.name == 'Mail-In Rebate' and
            not context.other_card.debuff and
            context.other_card:get_id() == G.GAME.current_round.mail_card.id then
                ease_dollars(self.ability.extra)
                return {
                    message = localize('$')..self.ability.extra,
                    colour = G.C.MONEY,
                    card = self
                }
            end
            if self.ability.name == 'Hit the Road' and
            not context.other_card.debuff and
            context.other_card:get_id() == 11 and not context.blueprint then
                self.ability.x_mult = self.ability.x_mult + self.ability.extra
                return {
                    message = localize{type='variable',key='a_xmult',vars={self.ability.x_mult}},
                        colour = G.C.RED,
                        delay = 0.45, 
                    card = self
                }
            end
            if self.ability.name == 'Green Joker' and not context.blueprint and context.other_card == context.full_hand[#context.full_hand] then
                local prev_mult = self.ability.mult
                self.ability.mult = math.max(0, self.ability.mult - self.ability.extra.discard_sub)
                if self.ability.mult ~= prev_mult then 
                    return {
                        message = localize{type='variable',key='a_mult_minus',vars={self.ability.extra.discard_sub}},
                        colour = G.C.RED,
                        card = self
                    }
                end
            end
            
            if self.ability.name == 'Faceless Joker' and context.other_card == context.full_hand[#context.full_hand] then
                local face_cards = 0
                for k, v in ipairs(context.full_hand) do
                    if v:is_face() then face_cards = face_cards + 1 end
                end
                if face_cards >= self.ability.extra.faces then
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            ease_dollars(self.ability.extra.dollars)
                            card_eval_status_text(context.blueprint_card or self, 'extra', nil, nil, nil, {message = localize('$')..self.ability.extra.dollars,colour = G.C.MONEY, delay = 0.45})
                            return true
                        end}))
                    return
        nil, true                end
            end
            return
        elseif context.end_of_round then
            if context.individual then

            elseif context.repetition then
                if context.cardarea == G.hand then
                    if self.ability.name == 'Mime' and
                    (next(context.card_effects[1]) or #context.card_effects > 1) then
                        return {
                            message = localize('k_again_ex'),
                            repetitions = self.ability.extra,
                            card = self
                        }
                    end
                end
            elseif not context.blueprint then
                if self.ability.name == 'Campfire' and G.GAME.blind.boss and self.ability.x_mult > 1 then
                    self.ability.x_mult = 1
                    return {
                        message = localize('k_reset'),
                        colour = G.C.RED
                    }
                end
                if self.ability.name == 'Rocket' and G.GAME.blind.boss then
                    self.ability.extra.dollars = self.ability.extra.dollars + self.ability.extra.increase
                    return {
                        message = localize('k_upgrade_ex'),
                        colour = G.C.MONEY
                    }
                end
                if self.ability.name == 'Turtle Bean' and not context.blueprint then
                    if self.ability.extra.h_size - self.ability.extra.h_mod <= 0 then 
                        G.E_MANAGER:add_event(Event({
                            func = function()
                                play_sound('tarot1')
                                self.T.r = -0.2
                                self:juice_up(0.3, 0.4)
                                self.states.drag.is = true
                                self.children.center.pinch.x = true
                                G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, blockable = false,
                                    func = function()
                                            G.jokers:remove_card(self)
                                            self:remove()
                                            self = nil
                                        return true; end})) 
                                return true
                            end
                        })) 
                        return {
                            card = self,
                            message = localize('k_eaten_ex'),
                            colour = G.C.FILTER
                        }
                    else
                        self.ability.extra.h_size = self.ability.extra.h_size - self.ability.extra.h_mod
                        G.hand:change_size(- self.ability.extra.h_mod)
                        return {
                            message = localize{type='variable',key='a_handsize_minus',vars={self.ability.extra.h_mod}},
                            colour = G.C.FILTER
                        }
                    end
                end
                if self.ability.name == 'Invisible Joker' and not context.blueprint then
                    self.ability.invis_rounds = self.ability.invis_rounds + 1
                    if self.ability.invis_rounds == self.ability.extra then 
                        local eval = function(card) return not card.REMOVED end
                        juice_card_until(self, eval, true)
                    end
                    return {
                        message = (self.ability.invis_rounds < self.ability.extra) and (self.ability.invis_rounds..'/'..self.ability.extra) or localize('k_active_ex'),
                        colour = G.C.FILTER
                    }
                end
                if self.ability.name == 'Popcorn' and not context.blueprint then
                    if self.ability.mult - self.ability.extra <= 0 then 
                        G.E_MANAGER:add_event(Event({
                            func = function()
                                play_sound('tarot1')
                                self.T.r = -0.2
                                self:juice_up(0.3, 0.4)
                                self.states.drag.is = true
                                self.children.center.pinch.x = true
                                G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, blockable = false,
                                    func = function()
                                            G.jokers:remove_card(self)
                                            self:remove()
                                            self = nil
                                        return true; end})) 
                                return true
                            end
                        })) 
                        return {
                            message = localize('k_eaten_ex'),
                            colour = G.C.RED
                        }
                    else
                        self.ability.mult = self.ability.mult - self.ability.extra
                        return {
                            message = localize{type='variable',key='a_mult_minus',vars={self.ability.extra}},
                            colour = G.C.MULT
                        }
                    end
                end
                if self.ability.name == 'To Do List' and not context.blueprint then
                    local _poker_hands = {}
                    for k, v in pairs(G.GAME.hands) do
                        if v.visible and k ~= self.ability.to_do_poker_hand then _poker_hands[#_poker_hands+1] = k end
                    end
                    self.ability.to_do_poker_hand = pseudorandom_element(_poker_hands, pseudoseed('to_do'))
                    return {
                        message = localize('k_reset')
                    }
                end
                if self.ability.name == 'Egg' then
                    self.ability.extra_value = self.ability.extra_value + self.ability.extra
                    self:set_cost()
                    return {
                        message = localize('k_val_up'),
                        colour = G.C.MONEY
                    }
                end
                if self.ability.name == 'Gift Card' then
                    for k, v in ipairs(G.jokers.cards) do
                        if v.set_cost then 
                            v.ability.extra_value = (v.ability.extra_value or 0) + self.ability.extra
                            v:set_cost()
                        end
                    end
                    for k, v in ipairs(G.consumeables.cards) do
                        if v.set_cost then 
                            v.ability.extra_value = (v.ability.extra_value or 0) + self.ability.extra
                            v:set_cost()
                        end
                    end
                    return {
                        message = localize('k_val_up'),
                        colour = G.C.MONEY
                    }
                end
                if self.ability.name == 'Hit the Road' and to_big(self.ability.x_mult) > to_big(1) then
                    self.ability.x_mult = 1
                    return {
                        message = localize('k_reset'),
                        colour = G.C.RED
                    }
                end
                
                if self.ability.name == 'Gros Michel' or self.ability.name == 'Cavendish' then
                    if pseudorandom(self.ability.name == 'Cavendish' and 'cavendish' or 'gros_michel') < cry_prob(self.ability.cry_prob, self.ability.extra.odds, self.ability.cry_rigged)/self.ability.extra.odds then
                        G.E_MANAGER:add_event(Event({
                            func = function()
                                play_sound('tarot1')
                                self.T.r = -0.2
                                self:juice_up(0.3, 0.4)
                                self.states.drag.is = true
                                self.children.center.pinch.x = true
                                G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, blockable = false,
                                    func = function()
                                            G.jokers:remove_card(self)
                                            self:remove()
                                            self = nil
                                        return true; end})) 
                                return true
                            end
                        })) 
                        if self.ability.name == 'Gros Michel' then G.GAME.pool_flags.gros_michel_extinct = true end
                        return {
                            message = localize('k_extinct_ex')
                        }
                    else
                        return {
                            message = localize('k_safe_ex')
                        }
                    end
                end
                if self.ability.name == 'Mr. Bones' and context.game_over and 
                to_big(G.GAME.chips)/G.GAME.blind.chips >= to_big(0.25) then
                    G.E_MANAGER:add_event(Event({
                        func = function()
                            G.hand_text_area.blind_chips:juice_up()
                            G.hand_text_area.game_chips:juice_up()
                            play_sound('tarot1')
                            self:start_dissolve()
                            return true
                        end
                    })) 
                    return {
                        message = localize('k_saved_ex'),
                        saved = true,
                        colour = G.C.RED
                    }
                end
            end
        elseif context.individual then
        if context.cardarea == G.play then
        	if self.edition and self.edition.jen_wee and context.other_card:get_id() == 2 then
        		if ((self.config or {}).center or {}).wee_incompatible or ((self.config or {}).center or {}).key == 'j_cry_weegaming' then
        			card_eval_status_text(self, 'extra', nil, nil, nil, {message = 'Can\'t upgrade!', nopeus_again = true, colour = G.C.RED})
        		else
        			self.edition.twos_scored = (self.edition.twos_scored or 0) + (G.GAME.weeck and 3 or 1)
        			card_eval_status_text(self, 'extra', nil, nil, nil, {message = localize('k_upgrade_ex') .. " : " .. (tostring(100 + (8*self.edition.twos_scored)) .. '%'), colour = G.C.DARK_EDITION})
        			self:remove_from_deck()
        			Cryptid.misprintize(self, {min = 1 + (0.08 * self.edition.twos_scored),max = 1 + (0.08 * self.edition.twos_scored)})
        			self:add_to_deck()
        		end
        	end
        end
            if context.cardarea == G.play then
                if self.ability.name == 'Hiker' then
                        context.other_card.ability.perma_bonus = context.other_card.ability.perma_bonus or 0
                        context.other_card.ability.perma_bonus = context.other_card.ability.perma_bonus + self.ability.extra
                        return {
                            extra = {message = localize('k_upgrade_ex'), colour = G.C.CHIPS},
                            colour = G.C.CHIPS,
                            card = self
                        }
                end
                if self.ability.name == 'Lucky Cat' and context.other_card.lucky_trigger and not context.blueprint then
                    self.ability.x_mult = self.ability.x_mult + self.ability.extra
                    return {
                        extra = {focus = self, message = localize('k_upgrade_ex'), colour = G.C.MULT},
                        card = self
                    }
                end
                if self.ability.name == 'Wee Joker' and
                    context.other_card:get_id() == 2 and not context.blueprint then
                        self.ability.extra.chips = self.ability.extra.chips + self.ability.extra.chip_mod
                        
                        return {
                            extra = {focus = self, message = localize('k_upgrade_ex')},
                            card = self,
                            colour = G.C.CHIPS
                        }
                end
                if self.ability.name == 'Photograph' then
                    local first_face = nil
                    for i = 1, #context.scoring_hand do
                        if context.scoring_hand[i]:is_face() then first_face = context.scoring_hand[i]; break end
                    end
                    if context.other_card == first_face then
                        return {
                            x_mult = self.ability.extra,
                            colour = G.C.RED,
                            card = self
                        }
                    end
                end
                if self.ability.name == '8 Ball' and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
                    if (context.other_card:get_id() == 8) and (pseudorandom('8ball') < cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged)/self.ability.extra) then
                        G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
                        return {
                            extra = {focus = self, message = localize('k_plus_tarot'), func = function()
                                G.E_MANAGER:add_event(Event({
                                    trigger = 'before',
                                    delay = 0.0,
                                    func = (function()
                                            local card = create_card('Tarot',G.consumeables, nil, nil, nil, nil, nil, '8ba')
                                            card:add_to_deck()
                                            G.consumeables:emplace(card)
                                            G.GAME.consumeable_buffer = 0
                                        return true
                                    end)}))
                            end},
                            colour = G.C.SECONDARY_SET.Tarot,
                            card = self
                        }
                    end
                end
                if self.ability.name == 'The Idol' and
                    context.other_card:get_id() == G.GAME.current_round.idol_card.id and 
                    context.other_card:is_suit(G.GAME.current_round.idol_card.suit) then
                        return {
                            x_mult = self.ability.extra,
                            colour = G.C.RED,
                            card = self
                        }
                    end
                if self.ability.name == 'Scary Face' and (
                    context.other_card:is_face()) then
                        return {
                            chips = self.ability.extra,
                            card = self
                        }
                    end
                if self.ability.name == 'Smiley Face' and (
                    context.other_card:is_face()) then
                        return {
                            mult = self.ability.extra,
                            card = self
                        }
                    end
                if self.ability.name == 'Golden Ticket' and
                    SMODS.has_enhancement(context.other_card, 'm_gold') then
                        G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + self.ability.extra
                        if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
                        return {
                            dollars = self.ability.extra,
                            card = self
                        }
                    end
                if self.ability.name == 'Scholar' and
                    context.other_card:get_id() == 14 then
                        return {
                            chips = self.ability.extra.chips,
                            mult = self.ability.extra.mult,
                            card = self
                        }
                    end
                if self.ability.name == 'Walkie Talkie' and
                (context.other_card:get_id() == 10 or context.other_card:get_id() == 4) then
                    return {
                        chips = self.ability.extra.chips,
                        mult = self.ability.extra.mult,
                        card = self
                    }
                end
                if self.ability.name == 'Business Card' and
                    context.other_card:is_face() and
                    pseudorandom('business') < cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged)/self.ability.extra then
                        G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + 2
                        if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
                        return {
                            dollars = 2,
                            card = self
                        }
                    end
                if self.ability.name == 'Fibonacci' and (
                context.other_card:get_id() == 2 or 
                context.other_card:get_id() == 3 or 
                context.other_card:get_id() == 5 or 
                context.other_card:get_id() == 8 or 
                context.other_card:get_id() == 14) then
                    return {
                        mult = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Even Steven' and
                context.other_card:get_id() <= 10 and 
                context.other_card:get_id() >= 0 and
                context.other_card:get_id()%2 == 0
                then
                    return {
                        mult = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Odd Todd' and
                ((context.other_card:get_id() <= 10 and 
                context.other_card:get_id() >= 0 and
                context.other_card:get_id()%2 == 1) or
                (context.other_card:get_id() == 14))
                then
                    return {
                        chips = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.effect == 'Suit Mult' and
                    context.other_card:is_suit(self.ability.extra.suit) then
                    return {
                        mult = self.ability.extra.s_mult,
                        card = self
                    }
                end
                if self.ability.name == 'Rough Gem' and
                context.other_card:is_suit("Diamonds") then
                    G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + self.ability.extra
                    if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
                    return {
                        dollars = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Onyx Agate' and
                context.other_card:is_suit("Clubs") then
                    return {
                        mult = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Arrowhead' and
                context.other_card:is_suit("Spades") then
                    return {
                        chips = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name ==  'Bloodstone' and
                context.other_card:is_suit("Hearts") and 
                pseudorandom('bloodstone') < cry_prob(self.ability.cry_prob, self.ability.extra.odds, self.ability.cry_rigged)/self.ability.extra.odds then
                    return {
                        x_mult = self.ability.extra.Xmult,
                        card = self
                    }
                end
                if self.ability.name == 'Ancient Joker' and
                context.other_card:is_suit(G.GAME.current_round.ancient_card.suit) then
                    return {
                        x_mult = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Triboulet' and
                    (context.other_card:get_id() == 12 or context.other_card:get_id() == 13) then
                        return {
                            x_mult = self.ability.extra,
                            colour = G.C.RED,
                            card = self
                        }
                    end
            end
            if context.cardarea == G.hand then
                    if self.ability.name == 'Shoot the Moon' and
                        context.other_card:get_id() == 12 then
                        if context.other_card.debuff then
                            return {
                                message = localize('k_debuffed'),
                                colour = G.C.RED,
                                card = self,
                            }
                        else
                            return {
                                h_mult = 13,
                                card = self
                            }
                        end
                    end
                    if self.ability.name == 'Baron' and
                        context.other_card:get_id() == 13 then
                        if context.other_card.debuff then
                            return {
                                message = localize('k_debuffed'),
                                colour = G.C.RED,
                                card = self,
                            }
                        else
                            return {
                                x_mult = self.ability.extra,
                                card = self
                            }
                        end
                    end
                    if self.ability.name == 'Reserved Parking' and
                    context.other_card:is_face() and
                    pseudorandom('parking') < cry_prob(self.ability.cry_prob, self.ability.extra.odds, self.ability.cry_rigged)/self.ability.extra.odds then
                        if context.other_card.debuff then
                            return {
                                message = localize('k_debuffed'),
                                colour = G.C.RED,
                                card = self,
                            }
                        else
                            G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + self.ability.extra.dollars
                            if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
                            return {
                                dollars = self.ability.extra.dollars,
                                card = self
                            }
                        end
                    end
                    if self.ability.name == 'Raised Fist' then
                        local temp_Mult, temp_ID = 15, 15
                        local raised_card = nil
                        for i=1, #G.hand.cards do
                            if temp_ID >= G.hand.cards[i].base.id and not SMODS.has_no_rank(G.hand.cards[i]) then 
                                temp_Mult = G.hand.cards[i].base.nominal
                                temp_ID = G.hand.cards[i].base.id
                                raised_card = G.hand.cards[i]
                            end
                        end
                        if raised_card == context.other_card then 
                            if context.other_card.debuff then
                                return {
                                    message = localize('k_debuffed'),
                                    colour = G.C.RED,
                                    card = self,
                                }
                            else
                                return {
                                    h_mult = 2*temp_Mult,
                                    card = self,
                                }
                            end
                        end
                    end
            end
        elseif context.repetition then
            if context.cardarea == G.play then
                if self.ability.name == 'Sock and Buskin' and (
                context.other_card:is_face()) then
                    return {
                        message = localize('k_again_ex'),
                        repetitions = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Hanging Chad' and (
                context.other_card == context.scoring_hand[1]) then
                    return {
                        message = localize('k_again_ex'),
                        repetitions = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Dusk' and G.GAME.current_round.hands_left == 0 then
                    return {
                        message = localize('k_again_ex'),
                        repetitions = self.ability.extra,
                        card = self
                    }
                end
                if self.ability.name == 'Seltzer' then
                    return {
                        message = localize('k_again_ex'),
                        repetitions = 1,
                        card = self
                    }
                end
                if self.ability.name == 'Hack' and (
                context.other_card:get_id() == 2 or 
                context.other_card:get_id() == 3 or 
                context.other_card:get_id() == 4 or 
                context.other_card:get_id() == 5) then
                    return {
                        message = localize('k_again_ex'),
                        repetitions = self.ability.extra,
                        card = self
                    }
                end
            end
            if context.cardarea == G.hand then
                if self.ability.name == 'Mime' and
                (next(context.card_effects[1]) or #context.card_effects > 1) then
                    return {
                        message = localize('k_again_ex'),
                        repetitions = self.ability.extra,
                        card = self
                    }
                end
            end
        elseif context.other_joker then
            if self.ability.name == 'Baseball Card' and (context.other_joker.config.center.rarity == 2 or context.other_joker.config.center.rarity == "Uncommon") and self ~= context.other_joker then
                G.E_MANAGER:add_event(Event({
                    func = function()
                        context.other_joker:juice_up(0.5, 0.5)
                        return true
                    end
                })) 
                return {
                    message = localize{type='variable',key='a_xmult',vars={self.ability.extra}},
                    Xmult_mod = self.ability.extra
                }
            end
        else
            do
                if context.before then
                    if self.ability.name == 'Spare Trousers' and (next(context.poker_hands['Two Pair']) or next(context.poker_hands['Full House'])) and not context.blueprint then
                        self.ability.mult = self.ability.mult + self.ability.extra
                        return {
                            message = localize('k_upgrade_ex'),
                            colour = G.C.RED,
                            card = self
                        }
                    end
                    if self.ability.name == 'Space Joker' and pseudorandom('space') < cry_prob(self.ability.cry_prob, self.ability.extra, self.ability.cry_rigged)/self.ability.extra then
                        return {
                            card = self,
                            level_up = true,
                            message = localize('k_level_up_ex')
                        }
                    end
                    if self.ability.name == 'Square Joker' and #context.full_hand == 4 and not context.blueprint then
                        self.ability.extra.chips = self.ability.extra.chips + self.ability.extra.chip_mod
                        return {
                            message = localize('k_upgrade_ex'),
                            colour = G.C.CHIPS,
                            card = self
                        }
                    end
                    if self.ability.name == 'Runner' and next(context.poker_hands['Straight']) and not context.blueprint then
                        self.ability.extra.chips = self.ability.extra.chips + self.ability.extra.chip_mod
                        return {
                            message = localize('k_upgrade_ex'),
                            colour = G.C.CHIPS,
                            card = self
                        }
                    end
                    if self.ability.name == 'Midas Mask' and not context.blueprint then
                        local faces = {}
                        for k, v in ipairs(context.scoring_hand) do
                            if v:is_face() then 
                                faces[#faces+1] = v
                                v:set_ability(G.P_CENTERS.m_gold, nil, true)
                                G.E_MANAGER:add_event(Event({
                                    func = function()
                                        v:juice_up()
                                        return true
                                    end
                                })) 
                            end
                        end
                        if #faces > 0 then 
                            return {
                                message = localize('k_gold'),
                                colour = G.C.MONEY,
                                card = self
                            }
                        end
                    end
                    if self.ability.name == 'Vampire' and not context.blueprint then
                        local enhanced = {}
                        for k, v in ipairs(context.scoring_hand) do
                            if v.config.center ~= G.P_CENTERS.c_base and not v.debuff and not v.vampired then 
                                enhanced[#enhanced+1] = v
                                v.vampired = true
                                v:set_ability(G.P_CENTERS.c_base, nil, true)
                                G.E_MANAGER:add_event(Event({
                                    func = function()
                                        v:juice_up()
                                        v.vampired = nil
                                        return true
                                    end
                                })) 
                            end
                        end

                        if #enhanced > 0 then 
                            self.ability.x_mult = self.ability.x_mult + self.ability.extra*#enhanced
                            return {
                                message = localize{type='variable',key='a_xmult',vars={self.ability.x_mult}},
                                colour = G.C.MULT,
                                card = self
                            }
                        end
                    end
                    if self.ability.name == 'To Do List' and context.scoring_name == self.ability.to_do_poker_hand then
                        ease_dollars(self.ability.extra.dollars)
                        G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + self.ability.extra.dollars
                        if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
                        return {
                            message = localize('$')..self.ability.extra.dollars,
                            colour = G.C.MONEY
                        }
                    end
                    if self.ability.name == 'DNA' and G.GAME.current_round.hands_played == 0 then
                        if #context.full_hand == 1 then
                            G.playing_card = (G.playing_card and G.playing_card + 1) or 1
                            local _card = copy_card(context.full_hand[1], nil, nil, G.playing_card)
                            _card:add_to_deck()
                            G.deck.config.card_limit = G.deck.config.card_limit + 1
                            table.insert(G.playing_cards, _card)
                            G.hand:emplace(_card)
                            _card.states.visible = nil

                            G.E_MANAGER:add_event(Event({
                                func = function()
                                    _card:start_materialize()
                                    return true
                                end
                            })) 
                            return {
                                message = localize('k_copied_ex'),
                                colour = G.C.CHIPS,
                                card = self,
                                playing_cards_created = {true}
                            }
                        end
                    end
                    if self.ability.name == 'Ride the Bus' and not context.blueprint then
                        local faces = false
                        for i = 1, #context.scoring_hand do
                            if context.scoring_hand[i]:is_face() then faces = true end
                        end
                        if faces then
                            local last_mult = self.ability.mult
                            self.ability.mult = 0
                            if last_mult > 0 then 
                                return {
                                    card = self,
                                    message = localize('k_reset')
                                }
                            end
                        else
                            self.ability.mult = self.ability.mult + self.ability.extra
                        end
                    end
                    if self.ability.name == 'Obelisk' and not context.blueprint then
                        local reset = true
                        local play_more_than = (G.GAME.hands[context.scoring_name].played or 0)
                        for k, v in pairs(G.GAME.hands) do
                            if k ~= context.scoring_name and v.played >= play_more_than and v.visible then
                                reset = false
                            end
                        end
                        if reset then
                            if to_big(self.ability.x_mult) > to_big(1) then
                                self.ability.x_mult = 1
                                return {
                                    card = self,
                                    message = localize('k_reset')
                                }
                            end
                        else
                            self.ability.x_mult = self.ability.x_mult + self.ability.extra
                        end
                    end
                    if self.ability.name == 'Green Joker' and not context.blueprint then
                        self.ability.mult = self.ability.mult + self.ability.extra.hand_add
                        return {
                            card = self,
                            message = localize{type='variable',key='a_mult',vars={self.ability.extra.hand_add}}
                        }
                    end
                elseif context.after then
                    if self.ability.name == 'Ice Cream' and not context.blueprint then
                        if self.ability.extra.chips - self.ability.extra.chip_mod <= 0 then 
                            G.E_MANAGER:add_event(Event({
                                func = function()
                                    play_sound('tarot1')
                                    self.T.r = -0.2
                                    self:juice_up(0.3, 0.4)
                                    self.states.drag.is = true
                                    self.children.center.pinch.x = true
                                    G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, blockable = false,
                                        func = function()
                                                G.jokers:remove_card(self)
                                                self:remove()
                                                self = nil
                                            return true; end})) 
                                    return true
                                end
                            })) 
                            return {
                                message = localize('k_melted_ex'),
                                colour = G.C.CHIPS
                            }
                        else
                            self.ability.extra.chips = self.ability.extra.chips - self.ability.extra.chip_mod
                            return {
                                message = localize{type='variable',key='a_chips_minus',vars={self.ability.extra.chip_mod}},
                                colour = G.C.CHIPS
                            }
                        end
                    end
                    if self.ability.name == 'Seltzer' and not context.blueprint then
                        if self.ability.extra - 1 <= 0 then 
                            G.E_MANAGER:add_event(Event({
                                func = function()
                                    play_sound('tarot1')
                                    self.T.r = -0.2
                                    self:juice_up(0.3, 0.4)
                                    self.states.drag.is = true
                                    self.children.center.pinch.x = true
                                    G.E_MANAGER:add_event(Event({trigger = 'after', delay = 0.3, blockable = false,
                                        func = function()
                                                G.jokers:remove_card(self)
                                                self:remove()
                                                self = nil
                                            return true; end})) 
                                    return true
                                end
                            })) 
                            return {
                                message = localize('k_drank_ex'),
                                colour = G.C.FILTER
                            }
                        else
                            self.ability.extra = self.ability.extra - 1
                            return {
                                message = self.ability.extra..'',
                                colour = G.C.FILTER
                            }
                        end
                    end
                elseif context.joker_main then
                        if self.ability.name == 'Loyalty Card' then
                            self.ability.loyalty_remaining = (self.ability.extra.every-1-(G.GAME.hands_played - self.ability.hands_played_at_create))%(self.ability.extra.every+1)
                            if context.blueprint then
                                if self.ability.loyalty_remaining == self.ability.extra.every then
                                    return {
                                        message = localize{type='variable',key='a_xmult',vars={self.ability.extra.Xmult}},
                                        Xmult_mod = self.ability.extra.Xmult
                                    }
                                end
                            else
                                if self.ability.loyalty_remaining == 0 then
                                    local eval = function(card) return (card.ability.loyalty_remaining == 0) end
                                    juice_card_until(self, eval, true)
                                elseif self.ability.loyalty_remaining == self.ability.extra.every then
                                    return {
                                        message = localize{type='variable',key='a_xmult',vars={self.ability.extra.Xmult}},
                                        Xmult_mod = self.ability.extra.Xmult
                                    }
                                end
                            end
                        end
                        if self.ability.name ~= 'Seeing Double' and to_big(self.ability.x_mult) > to_big(1) and (self.ability.type == '' or next(context.poker_hands[self.ability.type])) then
                            return {
                                message = localize{type='variable',key='a_xmult',vars={self.ability.x_mult}},
                                colour = G.C.RED,
                                Xmult_mod = self.ability.x_mult
                            }
                        end
                        if to_big(self.ability.t_mult) > to_big(0) and next(context.poker_hands[self.ability.type]) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.t_mult}},
                                mult_mod = self.ability.t_mult
                            }
                        end
                        if to_big(self.ability.t_chips) > to_big(0) and next(context.poker_hands[self.ability.type]) then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.t_chips}},
                                chip_mod = self.ability.t_chips
                            }
                        end
                        if self.ability.name == 'Half Joker' and #context.full_hand <= self.ability.extra.size then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.extra.mult}},
                                mult_mod = self.ability.extra.mult
                            }
                        end
                        if self.ability.name == 'Abstract Joker' then
                            local x = 0
                            for i = 1, #G.jokers.cards do
                                if G.jokers.cards[i].ability.set == 'Joker' then x = x + 1 end
                            end
                            return {
                                message = localize{type='variable',key='a_mult',vars={x*self.ability.extra}},
                                mult_mod = x*self.ability.extra
                            }
                        end
                        if self.ability.name == 'Acrobat' and G.GAME.current_round.hands_left == 0 then
                            return {
                                message = localize{type='variable',key='a_xmult',vars={self.ability.extra}},
                                Xmult_mod = self.ability.extra
                            }
                        end
                        if self.ability.name == 'Mystic Summit' and G.GAME.current_round.discards_left == self.ability.extra.d_remaining then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.extra.mult}},
                                mult_mod = self.ability.extra.mult
                            }
                        end
                        if self.ability.name == 'Misprint' then
                            local temp_Mult = pseudorandom('misprint', self.ability.extra.min, self.ability.extra.max)
                            return {
                                message = localize{type='variable',key='a_mult',vars={temp_Mult}},
                                mult_mod = temp_Mult
                            }
                        end
                        if self.ability.name == 'Banner' and G.GAME.current_round.discards_left > 0 then
                            return {
                                message = localize{type='variable',key='a_chips',vars={G.GAME.current_round.discards_left*self.ability.extra}},
                                chip_mod = G.GAME.current_round.discards_left*self.ability.extra
                            }
                        end
                        if self.ability.name == 'Stuntman' then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra.chip_mod}},
                                chip_mod = self.ability.extra.chip_mod,
                            }
                        end
                        if self.ability.name == 'Matador' then
                            if G.GAME.blind.triggered then 
                                ease_dollars(self.ability.extra)
                                G.GAME.dollar_buffer = (G.GAME.dollar_buffer or 0) + self.ability.extra
                                if not Talisman.config_file.disable_anims then G.E_MANAGER:add_event(Event({func = (function() G.GAME.dollar_buffer = 0; return true end)})) else G.GAME.dollar_buffer = 0 end
                                return {
                                    message = localize('$')..self.ability.extra,
                                    colour = G.C.MONEY
                                }
                            end
                        end
                        if self.ability.name == 'Supernova' then
                            return {
                                message = localize{type='variable',key='a_mult',vars={G.GAME.hands[context.scoring_name].played}},
                                mult_mod = G.GAME.hands[context.scoring_name].played
                            }
                        end
                        if self.ability.name == 'Ceremonial Dagger' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Vagabond' and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
                            if to_big(G.GAME.dollars) <= to_big(self.ability.extra) then
                                G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
                                G.E_MANAGER:add_event(Event({
                                    trigger = 'before',
                                    delay = 0.0,
                                    func = (function()
                                            local card = create_card('Tarot',G.consumeables, nil, nil, nil, nil, nil, 'vag')
                                            card:add_to_deck()
                                            G.consumeables:emplace(card)
                                            G.GAME.consumeable_buffer = 0
                                        return true
                                    end)}))
                                return {
                                    message = localize('k_plus_tarot'),
                                    card = self
                                }
                            end
                        end
                        if self.ability.name == 'Superposition' and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
                            local aces = 0
                            for i = 1, #context.scoring_hand do
                                if context.scoring_hand[i]:get_id() == 14 then aces = aces + 1 end
                            end
                            if aces >= 1 and next(context.poker_hands["Straight"]) then
                                local card_type = 'Tarot'
                                G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
                                G.E_MANAGER:add_event(Event({
                                    trigger = 'before',
                                    delay = 0.0,
                                    func = (function()
                                            local card = create_card(card_type,G.consumeables, nil, nil, nil, nil, nil, 'sup')
                                            card:add_to_deck()
                                            G.consumeables:emplace(card)
                                            G.GAME.consumeable_buffer = 0
                                        return true
                                    end)}))
                                return {
                                    message = localize('k_plus_tarot'),
                                    colour = G.C.SECONDARY_SET.Tarot,
                                    card = self
                                }
                            end
                        end
                        if self.ability.name == 'Seance' and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
                            if next(context.poker_hands[self.ability.extra.poker_hand]) then
                                G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
                                G.E_MANAGER:add_event(Event({
                                    trigger = 'before',
                                    delay = 0.0,
                                    func = (function()
                                            local card = create_card('Spectral',G.consumeables, nil, nil, nil, nil, nil, 'sea')
                                            card:add_to_deck()
                                            G.consumeables:emplace(card)
                                            G.GAME.consumeable_buffer = 0
                                        return true
                                    end)}))
                                return {
                                    message = localize('k_plus_spectral'),
                                    colour = G.C.SECONDARY_SET.Spectral,
                                    card = self
                                }
                            end
                        end
                        if self.ability.name == 'Flower Pot' then
                            local suits = {
                                ['Hearts'] = 0,
                                ['Diamonds'] = 0,
                                ['Spades'] = 0,
                                ['Clubs'] = 0
                            }
                            for i = 1, #context.scoring_hand do
                                if not SMODS.has_any_suit(context.scoring_hand[i]) then
                                    if context.scoring_hand[i]:is_suit('Hearts', true) and suits["Hearts"] == 0 then suits["Hearts"] = suits["Hearts"] + 1
                                    elseif context.scoring_hand[i]:is_suit('Diamonds', true) and suits["Diamonds"] == 0  then suits["Diamonds"] = suits["Diamonds"] + 1
                                    elseif context.scoring_hand[i]:is_suit('Spades', true) and suits["Spades"] == 0  then suits["Spades"] = suits["Spades"] + 1
                                    elseif context.scoring_hand[i]:is_suit('Clubs', true) and suits["Clubs"] == 0  then suits["Clubs"] = suits["Clubs"] + 1 end
                                end
                            end
                            for i = 1, #context.scoring_hand do
                                if SMODS.has_any_suit(context.scoring_hand[i]) then
                                    if context.scoring_hand[i]:is_suit('Hearts') and suits["Hearts"] == 0 then suits["Hearts"] = suits["Hearts"] + 1
                                    elseif context.scoring_hand[i]:is_suit('Diamonds') and suits["Diamonds"] == 0  then suits["Diamonds"] = suits["Diamonds"] + 1
                                    elseif context.scoring_hand[i]:is_suit('Spades') and suits["Spades"] == 0  then suits["Spades"] = suits["Spades"] + 1
                                    elseif context.scoring_hand[i]:is_suit('Clubs') and suits["Clubs"] == 0  then suits["Clubs"] = suits["Clubs"] + 1 end
                                end
                            end
                            if suits["Hearts"] > 0 and
                            suits["Diamonds"] > 0 and
                            suits["Spades"] > 0 and
                            suits["Clubs"] > 0 then
                                return {
                                    message = localize{type='variable',key='a_xmult',vars={self.ability.extra}},
                                    Xmult_mod = self.ability.extra
                                }
                            end
                        end
                        if self.ability.name == 'Seeing Double' then
                            if SMODS.seeing_double_check(context.scoring_hand, 'Clubs') then
                                return {
                                    message = localize{type='variable',key='a_xmult',vars={self.ability.extra}},
                                    Xmult_mod = self.ability.extra
                                }
                            end
                        end
                        if self.ability.name == 'Wee Joker' then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra.chips}},
                                chip_mod = self.ability.extra.chips, 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == 'Castle' and (to_big(self.ability.extra.chips) > to_big(0)) then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra.chips}},
                                chip_mod = self.ability.extra.chips, 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == 'Blue Joker' and #G.deck.cards > 0 then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra*#G.deck.cards}},
                                chip_mod = self.ability.extra*#G.deck.cards, 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == 'Erosion' and (G.GAME.starting_deck_size - #G.playing_cards) > 0 then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.extra*(G.GAME.starting_deck_size - #G.playing_cards)}},
                                mult_mod = self.ability.extra*(G.GAME.starting_deck_size - #G.playing_cards), 
                                colour = G.C.MULT
                            }
                        end
                        if self.ability.name == 'Square Joker' then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra.chips}},
                                chip_mod = self.ability.extra.chips, 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == 'Runner' then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra.chips}},
                                chip_mod = self.ability.extra.chips, 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == 'Ice Cream' then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra.chips}},
                                chip_mod = self.ability.extra.chips, 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == 'Stone Joker' and self.ability.stone_tally > 0 then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra*self.ability.stone_tally}},
                                chip_mod = self.ability.extra*self.ability.stone_tally, 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == 'Steel Joker' and self.ability.steel_tally > 0 then
                            return {
                                message = localize{type='variable',key='a_xmult',vars={1 + self.ability.extra*self.ability.steel_tally}},
                                Xmult_mod = 1 + self.ability.extra*self.ability.steel_tally, 
                                colour = G.C.MULT
                            }
                        end
                        if self.ability.name == 'Bull' and to_big(G.GAME.dollars + (G.GAME.dollar_buffer or 0)) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_chips',vars={self.ability.extra*math.max(0,(G.GAME.dollars + (G.GAME.dollar_buffer or 0))) }},
                                chip_mod = self.ability.extra*math.max(0,(G.GAME.dollars + (G.GAME.dollar_buffer or 0))), 
                                colour = G.C.CHIPS
                            }
                        end
                        if self.ability.name == "Driver's License" then
                            if (self.ability.driver_tally or 0) >= 16 then 
                                return {
                                    message = localize{type='variable',key='a_xmult',vars={self.ability.extra}},
                                    Xmult_mod = self.ability.extra
                                }
                            end
                        end
                        if self.ability.name == "Blackboard" then
                            local black_suits, all_cards = 0, 0
                            for k, v in ipairs(G.hand.cards) do
                                all_cards = all_cards + 1
                                if v:is_suit('Clubs', nil, true) or v:is_suit('Spades', nil, true) then
                                    black_suits = black_suits + 1
                                end
                            end
                            if black_suits == all_cards then 
                                return {
                                    message = localize{type='variable',key='a_xmult',vars={self.ability.extra}},
                                    Xmult_mod = self.ability.extra
                                }
                            end
                        end
                        if self.ability.name == "Joker Stencil" then
                            if (G.jokers.config.card_limit - #G.jokers.cards) > 0 then
                                return {
                                    message = localize{type='variable',key='a_xmult',vars={self.ability.x_mult}},
                                    Xmult_mod = self.ability.x_mult
                                }
                            end
                        end
                        if self.ability.name == 'Swashbuckler' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Joker' then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Spare Trousers' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Ride the Bus' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Flash Card' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Popcorn' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Green Joker' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Fortune Teller' and G.GAME.consumeable_usage_total and G.GAME.consumeable_usage_total.tarot > 0 then
                            return {
                                message = localize{type='variable',key='a_mult',vars={G.GAME.consumeable_usage_total.tarot}},
                                mult_mod = G.GAME.consumeable_usage_total.tarot
                            }
                        end
                        if self.ability.name == 'Gros Michel' then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.extra.mult}},
                                mult_mod = self.ability.extra.mult,
                            }
                        end
                        if self.ability.name == 'Cavendish' then
                            return {
                                message = localize{type='variable',key='a_xmult',vars={self.ability.extra.Xmult}},
                                Xmult_mod = self.ability.extra.Xmult,
                            }
                        end
                        if self.ability.name == 'Red Card' and to_big(self.ability.mult) > to_big(0) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.mult}},
                                mult_mod = self.ability.mult
                            }
                        end
                        if self.ability.name == 'Card Sharp' and G.GAME.hands[context.scoring_name] and G.GAME.hands[context.scoring_name].played_this_round > 1 then
                            return {
                                message = localize{type='variable',key='a_xmult',vars={self.ability.extra.Xmult}},
                                Xmult_mod = self.ability.extra.Xmult,
                            }
                        end
                        if self.ability.name == 'Bootstraps' and to_big(math.floor((G.GAME.dollars + (G.GAME.dollar_buffer or 0))/self.ability.extra.dollars)) >= to_big(1) then
                            return {
                                message = localize{type='variable',key='a_mult',vars={self.ability.extra.mult*math.floor((G.GAME.dollars + (G.GAME.dollar_buffer or 0))/self.ability.extra.dollars)}},
                                mult_mod = self.ability.extra.mult*math.floor((G.GAME.dollars + (G.GAME.dollar_buffer or 0))/self.ability.extra.dollars)
                            }
                        end
                        if self.ability.name == 'Caino' and to_big(self.ability.caino_xmult) > to_big(1) then
                            return {
                                message = localize{type='variable',key='a_xmult',vars={self.ability.caino_xmult}},
                                Xmult_mod = self.ability.caino_xmult
                            }
                        end
                    end
                end
            end
        end
    end

function Card:is_suit(suit, bypass_debuff, flush_calc)
    if flush_calc then
        if SMODS.has_no_suit(self) then
            return false
        end
        if SMODS.has_any_suit(self) and self:can_calculate() then
            return true
        end
        if next(find_joker('Smeared Joker')) and SMODS.smeared_check(self, suit) then
            return true
        end
        return self.base.suit == suit
    else
        if self.debuff and not bypass_debuff then return end
        if SMODS.has_no_suit(self) then
            return false
        end
        if SMODS.has_any_suit(self) then
            return true
        end
        if next(find_joker('Smeared Joker')) and SMODS.smeared_check(self, suit) then
            return true
        end
        return self.base.suit == suit
    end
end

function Card:set_card_area(area)
    self.area = area
    self.parent = area
    self.layered_parallax = area.layered_parallax
end

function Card:remove_from_area()
    self.area = nil
    self.parent = nil
    self.layered_parallax = {x = 0, y = 0}
end

function Card:align()  
    if self.children.floating_sprite then 
        self.children.floating_sprite.T.y = self.T.y
        self.children.floating_sprite.T.x = self.T.x
        self.children.floating_sprite.T.r = self.T.r
    end

    if self.children.focused_ui then self.children.focused_ui:set_alignment() end
end

function Card:flip()
    if self.facing == 'front' then 
        self.flipping = 'f2b'
        self.facing='back'
        self.pinch.x = true
    elseif self.facing == 'back' then
        self.ability.wheel_flipped = nil
        self.flipping = 'b2f'
        self.facing='front'
        self.pinch.x = true
    end
end

function Card:update(dt)
    if self.flipping == 'f2b' then
        if self.sprite_facing == 'front' or true then
            if self.VT.w <= 0 then
                self.sprite_facing = 'back'
                self.pinch.x =false
            end
        end
    end
    if self.flipping == 'b2f' then
        if self.sprite_facing == 'back' or true then
            if self.VT.w <= 0 then
                self.sprite_facing = 'front'
                self.pinch.x =false
            end
        end
    end

    if not self.states.focus.is and self.children.focused_ui then
        self.children.focused_ui:remove()
        self.children.focused_ui = nil
    end

    self:update_alert()
    if self.ability.set == 'Joker' and not self.sticker_run then 
        self.sticker_run = get_joker_win_sticker(self.config.center) or 'NONE'
    end

    if self.ability.consumeable and self.ability.consumeable.max_highlighted then
        self.ability.consumeable.mod_num = self.ability.consumeable.max_highlighted
    end
    local obj = self.config.center
    if obj.update and type(obj.update) == 'function' then
        obj:update(self, dt)
    end
    local obj = G.P_SEALS[self.seal] or {}
    if obj.update and type(obj.update) == 'function' then
        obj:update(self, dt)
    end
    if G.STAGE == G.STAGES.RUN then
        if self.ability and self.ability.perma_debuff then self.debuff = true end
        if self.cry_debuff_immune then
        	self.debuff = false
        end

        if self.area and ((self.area == G.jokers) or (self.area == G.consumeables)) then
            self.bypass_lock = true
            self.bypass_discovery_center = true
            self.bypass_discovery_ui = true
        end
        self.sell_cost_label = (self.facing == 'back' and '?') or (G.GAME.modifiers.cry_no_sell_value and 0) or self.sell_cost

        if self.ability.name == 'Temperance' then
            self.ability.money = 0
            for i = 1, #G.jokers.cards do
                if G.jokers.cards[i].ability.set == 'Joker' then
                    self.ability.money = self.ability.money + G.jokers.cards[i].sell_cost
                end
            end
            self.ability.money = math.min(self.ability.money, self.ability.extra)
        end
        if self.ability.name == 'Throwback' then
            self.ability.x_mult = 1 + G.GAME.skips*self.ability.extra
        end
        if self.ability.name == "Driver's License" then 
            self.ability.driver_tally = 0
            for k, v in pairs(G.playing_cards) do
                if next(SMODS.get_enhancements(v)) then self.ability.driver_tally = self.ability.driver_tally+1 end
            end
        end
        if self.ability.name == "Steel Joker" then 
            self.ability.steel_tally = 0
            for k, v in pairs(G.playing_cards) do
                if SMODS.has_enhancement(v, 'm_steel') then self.ability.steel_tally = self.ability.steel_tally+1 end
            end
        end
        if self.ability.name == "Cloud 9" then 
            self.ability.nine_tally = 0
            for k, v in pairs(G.playing_cards) do
                if v:get_id() == 9 then self.ability.nine_tally = self.ability.nine_tally+1 end
            end
        end
        if self.ability.name == "Stone Joker" then 
            self.ability.stone_tally = 0
            for k, v in pairs(G.playing_cards) do
                if SMODS.has_enhancement(v, 'm_stone') then self.ability.stone_tally = self.ability.stone_tally+1 end
            end
        end
        if self.ability.name == "Joker Stencil" then 
            self.ability.x_mult = (G.jokers.config.card_limit - #G.jokers.cards)
            for i = 1, #G.jokers.cards do
                if G.jokers.cards[i].ability.name == 'Joker Stencil' then self.ability.x_mult = self.ability.x_mult + 1 end
            end
        end
        if self.ability.name == 'The Wheel of Fortune' then
            self.eligible_strength_jokers = EMPTY(self.eligible_strength_jokers)
            for k, v in pairs(G.jokers.cards) do
                if v.ability.set == 'Joker' and (not v.edition) then
                    table.insert(self.eligible_strength_jokers, v)
                end
            end
        end
        if self.ability.name == 'Ectoplasm' or self.ability.name == 'Hex' then
            self.eligible_editionless_jokers = EMPTY(self.eligible_editionless_jokers)
            for k, v in pairs(G.jokers.cards) do
                if v.ability.set == 'Joker' and (not v.edition) then
                    table.insert(self.eligible_editionless_jokers, v)
                end
            end
        end
        if self.ability.name == 'Blueprint' or self.ability.name == 'Brainstorm' then
            local other_joker = nil
            if self.ability.name == 'Brainstorm' then
                other_joker = G.jokers.cards[1]
            elseif self.ability.name == 'Blueprint' then
                for i = 1, #G.jokers.cards do
                    if G.jokers.cards[i] == self then other_joker = G.jokers.cards[i+1] end
                end
            end
            if other_joker and other_joker ~= self and other_joker.config.center.blueprint_compat then
                self.ability.blueprint_compat = 'compatible'
            else
                self.ability.blueprint_compat = 'incompatible'
            end
        end
        if self.ability.name == 'Swashbuckler' then
            local sell_cost = 0
            for i = 1, #G.jokers.cards do
                if G.jokers.cards[i] ~= self and (G.jokers.cards[i].area and G.jokers.cards[i].area == G.jokers) then
                    sell_cost = sell_cost + G.jokers.cards[i].sell_cost
                end
            end
            self.ability.mult = sell_cost
        end
    else
        if self.ability.name == 'Temperance' then
            self.ability.money = 0
        end
    end
end

function Card:hard_set_T(X, Y, W, H)
    local x = (X or self.T.x)
    local y = (Y or self.T.y)
    local w = (W or self.T.w)
    local h = (H or self.T.h)
    Moveable.hard_set_T(self,x, y, w, h)
    if self.children.front then self.children.front:hard_set_T(x, y, w, h) end
    self.children.back:hard_set_T(x, y, w, h)
    self.children.center:hard_set_T(x, y, w, h)
end

function Card:move(dt)
    Moveable.move(self, dt)
    --self:align()
    if self.children.h_popup then
        self.children.h_popup:set_alignment(self:align_h_popup())
    end
end

function Card:align_h_popup()
        local focused_ui = self.children.focused_ui and true or false
        local popup_direction = (self.children.buy_button or (self.area and self.area.config.view_deck) or (self.area and self.area.config.type == 'shop')) and 'cl' or 
                                (self.T.y < G.CARD_H*0.8) and 'bm' or
                                'tm'
        return {
            major = self.children.focused_ui or self,
            parent = self,
            xy_bond = 'Strong',
            r_bond = 'Weak',
            wh_bond = 'Weak',
            offset = {
                x = popup_direction ~= 'cl' and 0 or
                    focused_ui and -0.05 or
                    (self.ability.consumeable and 0.0) or
                    (self.ability.set == 'Voucher' and 0.0) or
                    -0.05,
                y = focused_ui and (
                            popup_direction == 'tm' and (self.area and self.area == G.hand and -0.08 or-0.15) or
                            popup_direction == 'bm' and 0.12 or
                            0
                        ) or
                    popup_direction == 'tm' and -0.13 or
                    popup_direction == 'bm' and 0.1 or
                    0
            },  
            type = popup_direction,
            --lr_clamp = true
        }
end

function Card:hover()
if Handy.controller.process_card_hover(self) then return end
    self:juice_up(0.05, 0.03)
    play_sound('paper1', math.random()*0.2 + 0.9, 0.35)

    --if this is the focused card
    if self.states.focus.is and not self.children.focused_ui then
        self.children.focused_ui = G.UIDEF.card_focus_ui(self)
    end

    if self.facing == 'front' and (not self.states.drag.is or G.CONTROLLER.HID.touch) and not self.no_ui and not G.debug_tooltip_toggle then 
        if self.children.alert and not self.config.center.alerted then
            self.config.center.alerted = true
            G:save_progress()
        elseif self.children.alert and self.seal and not G.P_SEALS[self.seal].alerted then
            G.P_SEALS[self.seal].alerted = true
            G:save_progress()
        end

        self.ability_UIBox_table = self:generate_UIBox_ability_table()
        self.config.h_popup = G.UIDEF.card_h_popup(self)
        self.config.h_popup_config = self:align_h_popup()

        Node.hover(self)
    end
end

function Card:stop_hover()
if Handy.last_hovered_card == self then
    Handy.last_hovered_card = nil
    Handy.last_hovered_area = nil
end
    Node.stop_hover(self)
end

function Card:juice_up(scale, rot_amount)
    --G.VIBRATION = G.VIBRATION + 0.4
    local rot_amt = rot_amount and 0.4*(math.random()>0.5 and 1 or -1)*rot_amount or (math.random()>0.5 and 1 or -1)*0.16
    scale = scale and scale*0.4 or 0.11
    Moveable.juice_up(self, scale, rot_amt)
end

function Card:draw(layer)
    layer = layer or 'both'

    self.hover_tilt = 1
    
    if not self.states.visible then return end
    if self.VT.x < -3 or self.VT.x > G.TILE_W + 2.5 then return end
    
    if (layer == 'shadow' or layer == 'both') then
        self.ARGS.send_to_shader = self.ARGS.send_to_shader or {}
        self.ARGS.send_to_shader[1] = math.min(self.VT.r*3, 1) + G.TIMERS.REAL/(28) + (self.juice and self.juice.r*20 or 0) + self.tilt_var.amt
        self.ARGS.send_to_shader[2] = G.TIMERS.REAL

        for k, v in pairs(self.children) do
            v.VT.scale = self.VT.scale
        end
    end

    G.shared_shadow = self.sprite_facing == 'front' and self.children.center or self.children.back

    --Draw the shadow
    if not self.no_shadow and G.SETTINGS.GRAPHICS.shadows == 'On' and((layer == 'shadow' or layer == 'both') and (self.ability.effect ~= 'Glass Card' and not self.greyed) and ((self.area and self.area ~= G.discard and self.area.config.type ~= 'deck') or not self.area or self.states.drag.is)) then
        self.shadow_height = 0*(0.08 + 0.4*math.sqrt(self.velocity.x^2)) + ((((self.highlighted and self.area == G.play) or self.states.drag.is) and 0.35) or (self.area and self.area.config.type == 'title_2') and 0.04 or 0.1)
        G.shared_shadow:draw_shader('dissolve', self.shadow_height)
    end

    if (layer == 'card' or layer == 'both') and self.area ~= G.hand then 
        if self.children.focused_ui then self.children.focused_ui:draw() end
    end
    
    if (layer == 'card' or layer == 'both') then
        -- for all hover/tilting:
        self.tilt_var = self.tilt_var or {mx = 0, my = 0, dx = self.tilt_var.dx or 0, dy = self.tilt_var.dy or 0, amt = 0}
        local tilt_factor = 0.3
        if self.states.focus.is then
            self.tilt_var.mx, self.tilt_var.my = G.CONTROLLER.cursor_position.x + self.tilt_var.dx*self.T.w*G.TILESCALE*G.TILESIZE, G.CONTROLLER.cursor_position.y + self.tilt_var.dy*self.T.h*G.TILESCALE*G.TILESIZE
            self.tilt_var.amt = math.abs(self.hover_offset.y + self.hover_offset.x - 1 + self.tilt_var.dx + self.tilt_var.dy - 1)*tilt_factor
        elseif self.states.hover.is then
            self.tilt_var.mx, self.tilt_var.my = G.CONTROLLER.cursor_position.x, G.CONTROLLER.cursor_position.y
            self.tilt_var.amt = math.abs(self.hover_offset.y + self.hover_offset.x - 1)*tilt_factor
        elseif self.ambient_tilt then
            local tilt_angle = G.TIMERS.REAL*(1.56 + (self.ID/1.14212)%1) + self.ID/1.35122
            self.tilt_var.mx = ((0.5 + 0.5*self.ambient_tilt*math.cos(tilt_angle))*self.VT.w+self.VT.x+G.ROOM.T.x)*G.TILESIZE*G.TILESCALE
            self.tilt_var.my = ((0.5 + 0.5*self.ambient_tilt*math.sin(tilt_angle))*self.VT.h+self.VT.y+G.ROOM.T.y)*G.TILESIZE*G.TILESCALE
            self.tilt_var.amt = self.ambient_tilt*(0.5+math.cos(tilt_angle))*tilt_factor
        end
        --Any particles
        if self.children.particles then self.children.particles:draw() end

        --Draw any tags/buttons
        if self.children.price then self.children.price:draw() end
        if self.children.buy_button then
            if self.highlighted then
                self.children.buy_button.states.visible = true
                self.children.buy_button:draw()
                if self.children.buy_and_use_button then 
                    self.children.buy_and_use_button:draw()
                end
            else
                self.children.buy_button.states.visible = false
            end
        end
        if self.children.use_button and self.highlighted then self.children.use_button:draw() end

        if self.vortex then
            if self.facing == 'back' then 
                self.children.back:draw_shader('vortex')
            else
                self.children.center:draw_shader('vortex')
                if self.children.front then 
                    self.children.front:draw_shader('vortex')
                end
            end

            love.graphics.setShader()
        elseif self.sprite_facing == 'front' then 
            --Draw the main part of the card
            if (self.edition and self.edition.negative) or (self.ability.name == 'Antimatter' and (self.config.center.discovered or self.bypass_discovery_center)) then
                self.children.center:draw_shader('negative', nil, self.ARGS.send_to_shader)
                if self.children.front and self.ability.effect ~= 'Stone Card' then
                    self.children.front:draw_shader('negative', nil, self.ARGS.send_to_shader)
                end
            elseif not self.greyed then
                self.children.center:draw_shader('dissolve')
                --If the card has a front, draw that next
                if self.children.front and self.ability.effect ~= 'Stone Card' then
                    self.children.front:draw_shader('dissolve')
                end
            end

            --If the card is not yet discovered
            if self.ability.set == 'Enhanced' then self.ability.consumeable = nil end
            if not self.config.center.discovered and (self.ability.consumeable or self.config.center.unlocked) and not self.config.center.demo and not self.bypass_discovery_center then
                local shared_sprite = (self.ability.set == 'Edition' or self.ability.set == 'Joker') and G.shared_undiscovered_joker or G.shared_undiscovered_tarot
                local scale_mod = -0.05 + 0.05*math.sin(1.8*G.TIMERS.REAL)
                local rotate_mod = 0.03*math.sin(1.219*G.TIMERS.REAL)

                shared_sprite.role.draw_major = self
                shared_sprite:draw_shader('dissolve', nil, nil, nil, self.children.center, scale_mod, rotate_mod)
            end

            if self.ability.name == 'Invisible Joker' and (self.config.center.discovered or self.bypass_discovery_center) then
                self.children.center:draw_shader('voucher', nil, self.ARGS.send_to_shader)
            end

            --If the card has any edition/seal, add that here
            if self.edition or self.seal or self.ability.eternal or self.ability.rental or self.ability.perishable or self.sticker or ((self.sticker_run and self.sticker_run ~= 'NONE') and G.SETTINGS.run_stake_stickers) or (self.ability.set == 'Spectral') or self.debuff or self.greyed or (self.ability.name == 'The Soul') or (self.ability.set == 'Voucher') or (self.ability.set == 'Booster') or self.config.center.soul_pos or self.config.center.demo then
                
                if (self.ability.set == 'Voucher' or self.config.center.demo) and (self.ability.name ~= 'Antimatter' or not (self.config.center.discovered or self.bypass_discovery_center)) then
                    self.children.center:draw_shader('voucher', nil, self.ARGS.send_to_shader)
                end
                if self.ability.set == 'Booster' or self.ability.set == 'Spectral' then
                    self.children.center:draw_shader('booster', nil, self.ARGS.send_to_shader)
                end
                if self.edition and self.edition.holo then
                    self.children.center:draw_shader('holo', nil, self.ARGS.send_to_shader)
                    if self.children.front and self.ability.effect ~= 'Stone Card' then
                        self.children.front:draw_shader('holo', nil, self.ARGS.send_to_shader)
                    end
                end
                if self.edition and self.edition.foil then
                    self.children.center:draw_shader('foil', nil, self.ARGS.send_to_shader)
                    if self.children.front and self.ability.effect ~= 'Stone Card' then
                        self.children.front:draw_shader('foil', nil, self.ARGS.send_to_shader)
                    end
                end
                if self.edition and self.edition.polychrome then
                    self.children.center:draw_shader('polychrome', nil, self.ARGS.send_to_shader)
                    if self.children.front and self.ability.effect ~= 'Stone Card' then
                        self.children.front:draw_shader('polychrome', nil, self.ARGS.send_to_shader)
                    end
                end
                if (self.edition and self.edition.negative) or (self.ability.name == 'Antimatter' and (self.config.center.discovered or self.bypass_discovery_center)) then
                    self.children.center:draw_shader('negative_shine', nil, self.ARGS.send_to_shader)
                end
                if self.seal then
                    G.shared_seals[self.seal].role.draw_major = self
                    G.shared_seals[self.seal]:draw_shader('dissolve', nil, nil, nil, self.children.center)
                    if self.seal == 'Gold' then G.shared_seals[self.seal]:draw_shader('voucher', nil, self.ARGS.send_to_shader, nil, self.children.center) end
                end
                if self.ability.eternal then
                    G.shared_sticker_eternal.role.draw_major = self
                    G.shared_sticker_eternal:draw_shader('dissolve', nil, nil, nil, self.children.center)
                    G.shared_sticker_eternal:draw_shader('voucher', nil, self.ARGS.send_to_shader, nil, self.children.center)
                end
                if self.ability.perishable and not layer then
                    G.shared_sticker_perishable.role.draw_major = self
                    G.shared_sticker_perishable:draw_shader('dissolve', nil, nil, nil, self.children.center)
                    G.shared_sticker_perishable:draw_shader('voucher', nil, self.ARGS.send_to_shader, nil, self.children.center)
                end
                if self.ability.rental then
                    G.shared_sticker_rental.role.draw_major = self
                    G.shared_sticker_rental:draw_shader('dissolve', nil, nil, nil, self.children.center)
                    G.shared_sticker_rental:draw_shader('voucher', nil, self.ARGS.send_to_shader, nil, self.children.center)
                end
                if self.sticker and G.shared_stickers[self.sticker] then
                    G.shared_stickers[self.sticker].role.draw_major = self
                    G.shared_stickers[self.sticker]:draw_shader('dissolve', nil, nil, nil, self.children.center)
                    G.shared_stickers[self.sticker]:draw_shader('voucher', nil, self.ARGS.send_to_shader, nil, self.children.center)
                elseif (self.sticker_run and G.shared_stickers[self.sticker_run]) and G.SETTINGS.run_stake_stickers then
                    G.shared_stickers[self.sticker_run].role.draw_major = self
                    G.shared_stickers[self.sticker_run]:draw_shader('dissolve', nil, nil, nil, self.children.center)
                    G.shared_stickers[self.sticker_run]:draw_shader('voucher', nil, self.ARGS.send_to_shader, nil, self.children.center)
                end

                if self.ability.name == 'The Soul' and (self.config.center.discovered or self.bypass_discovery_center) then
                    local scale_mod = 0.05 + 0.05*math.sin(1.8*G.TIMERS.REAL) + 0.07*math.sin((G.TIMERS.REAL - math.floor(G.TIMERS.REAL))*math.pi*14)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^3
                    local rotate_mod = 0.1*math.sin(1.219*G.TIMERS.REAL) + 0.07*math.sin((G.TIMERS.REAL)*math.pi*5)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^2
    
                    G.shared_soul.role.draw_major = self
                    G.shared_soul:draw_shader('dissolve',0, nil, nil, self.children.center,scale_mod, rotate_mod,nil, 0.1 + 0.03*math.sin(1.8*G.TIMERS.REAL),nil, 0.6)
                    G.shared_soul:draw_shader('dissolve', nil, nil, nil, self.children.center, scale_mod, rotate_mod)
                end

                if self.config.center.soul_pos and (self.config.center.discovered or self.bypass_discovery_center) then
                if self.config.center.soul_pos and self.config.center.soul_pos.extra and (self.config.center.discovered or self.bypass_discovery_center) then
                    local scale_mod = 0.07-- + 0.02*math.cos(1.8*G.TIMERS.REAL) + 0.00*math.cos((G.TIMERS.REAL - math.floor(G.TIMERS.REAL))*math.pi*14)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^3
                    local rotate_mod = 0--0.05*math.cos(1.219*G.TIMERS.REAL) + 0.00*math.cos((G.TIMERS.REAL)*math.pi*5)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^2
                    self.children.floating_sprite2:draw_shader('dissolve',0, nil, nil, self.children.center,scale_mod, rotate_mod,nil, 0.1--[[ + 0.03*math.cos(1.8*G.TIMERS.REAL)--]],nil, 0.6)
                    self.children.floating_sprite2:draw_shader('dissolve', nil, nil, nil, self.children.center, scale_mod, rotate_mod)
                end
                    local scale_mod = 0.07 + 0.02*math.sin(1.8*G.TIMERS.REAL) + 0.00*math.sin((G.TIMERS.REAL - math.floor(G.TIMERS.REAL))*math.pi*14)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^3
                    local rotate_mod = 0.05*math.sin(1.219*G.TIMERS.REAL) + 0.00*math.sin((G.TIMERS.REAL)*math.pi*5)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^2
    
                    if self.ability.name == 'Hologram' then
                        self.hover_tilt = self.hover_tilt*1.5
                        self.children.floating_sprite:draw_shader('hologram', nil, self.ARGS.send_to_shader, nil, self.children.center, 2*scale_mod, 2*rotate_mod)
                        self.hover_tilt = self.hover_tilt/1.5
                    else
                        self.children.floating_sprite:draw_shader('dissolve',0, nil, nil, self.children.center,scale_mod, rotate_mod,nil, 0.1 + 0.03*math.sin(1.8*G.TIMERS.REAL),nil, 0.6)
                        self.children.floating_sprite:draw_shader('dissolve', nil, nil, nil, self.children.center, scale_mod, rotate_mod)
                    end
                    
                end
                if self.debuff then
                    self.children.center:draw_shader('debuff', nil, self.ARGS.send_to_shader)
                    if self.children.front and self.ability.effect ~= 'Stone Card' then
                        self.children.front:draw_shader('debuff', nil, self.ARGS.send_to_shader)
                    end
                end
                if self.greyed then
                    self.children.center:draw_shader('played', nil, self.ARGS.send_to_shader)
                    if self.children.front and self.ability.effect ~= 'Stone Card' then
                        self.children.front:draw_shader('played', nil, self.ARGS.send_to_shader)
                    end
                end
            end 
        if self.pinned then
            G.shared_stickers['pinned'].role.draw_major = self
            G.shared_stickers['pinned']:draw_shader('dissolve', nil, nil, nil, self.children.center)
            G.shared_stickers['pinned']:draw_shader('voucher', nil, self.ARGS.send_to_shader, nil, self.children.center)
        end
            if self.blueprint_sprite_copy and self.children.floating_sprite then
                local scale_mod = 0.07 + 0.02*math.sin(1.8*G.TIMERS.REAL) + 0.00*math.sin((G.TIMERS.REAL - math.floor(G.TIMERS.REAL))*math.pi*14)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^3
                local rotate_mod = 0.05*math.sin(1.219*G.TIMERS.REAL) + 0.00*math.sin((G.TIMERS.REAL)*math.pi*5)*(1 - (G.TIMERS.REAL - math.floor(G.TIMERS.REAL)))^2
        
                if self.blueprint_copy_key == 'j_hologram' then
                    self.hover_tilt = self.hover_tilt*1.5
                    self.children.floating_sprite:draw_shader('hologram', nil, self.ARGS.send_to_shader, nil, self.children.center, 2*scale_mod, 2*rotate_mod)
                    self.hover_tilt = self.hover_tilt/1.5
                else
                    self.children.floating_sprite:draw_shader('dissolve',0, nil, nil, self.children.center,scale_mod, rotate_mod,nil, 0.1 + 0.03*math.sin(1.8*G.TIMERS.REAL),nil, 0.6)
                    self.children.floating_sprite:draw_shader('dissolve', nil, nil, nil, self.children.center, scale_mod, rotate_mod)
                end
                --self.children.floating_sprite:draw_shader('dissolve',   0, nil, nil, self.children.center, scale_mod, rotate_mod, nil, 0.1 + 0.03 * math.sin(1.8 * G.TIMERS.REAL), nil, 0.6)
                --self.children.floating_sprite:draw_shader('dissolve', nil, nil, nil, self.children.center, scale_mod, rotate_mod)
            end
        elseif self.sprite_facing == 'back' then
            local overlay = G.C.WHITE
            if self.area and self.area.config.type == 'deck' and self.rank > 3 then
                self.back_overlay = self.back_overlay or {}
                self.back_overlay[1] = 0.5 + ((#self.area.cards - self.rank)%7)/50
                self.back_overlay[2] = 0.5 + ((#self.area.cards - self.rank)%7)/50
                self.back_overlay[3] = 0.5 + ((#self.area.cards - self.rank)%7)/50
                self.back_overlay[4] = 1
                overlay = self.back_overlay
            end

            if self.area and self.area.config.type == 'deck' then
                if self.params.stake_chip then
                    if self.params.stake_chip_locked then 
                        self.children.back:draw(G.C.L_BLACK)
                    elseif self.params.chip_tower then
                        self.children.back:draw(G.C.WHITE)
                    elseif not self.children.back.won then
                        self.children.back:draw(Galdur.config.stake_colour == 1 and G.C.L_BLACK or G.C.WHITE)
                    else
                        self.children.back:draw(Galdur.config.stake_colour == 1 and G.C.WHITE or G.C.L_BLACK)
                    end
                else
                    self.children.back:draw(overlay)
                end
            else
                self.children.back:draw_shader('dissolve')
            end

            if self.sticker and G.shared_stickers[self.sticker] then
                G.shared_stickers[self.sticker].role.draw_major = self
                G.shared_stickers[self.sticker]:draw_shader('dissolve', nil, nil, true, self.children.center)
                if self.sticker == 'Gold' then G.shared_stickers[self.sticker]:draw_shader('voucher', nil, self.ARGS.send_to_shader, true, self.children.center) end
            end
        end

        for k, v in pairs(self.children) do
            if k ~= 'focused_ui' and k ~= "front" and k ~= "back" and k ~= "soul_parts" and k ~= "center" and k ~= 'floating_sprite' and k~= "shadow" and k~= "use_button" and k ~= 'buy_button' and k ~= 'buy_and_use_button' and k~= "debuff" and k ~= 'price' and k~= 'particles' and k ~= 'h_popup' then v:draw() end
        end

        if (layer == 'card' or layer == 'both') and self.area == G.hand then 
            if self.children.focused_ui then self.children.focused_ui:draw() end
        end

        add_to_drawhash(self)
        self:draw_boundingrect()
    end
end

function Card:release(dragged)
    if dragged:is(Card) and self.area then
        self.area:release(dragged)
    end
end 

function Card:highlight(is_higlighted)
    self.highlighted = is_higlighted
    if true then
        if self.highlighted and self.area and self.area.config.type ~= 'shop' and not self.area.config.collection then
            local x_off = (self.ability.consumeable and -0.1 or 0)
            self.children.use_button = UIBox{
                definition = G.UIDEF.use_and_sell_buttons(self), 
                config = {align=
                        ((self.area == G.jokers) or (self.area == G.consumeables)) and "cr" or
                        "bmi"
                    , offset = 
                        ((self.area == G.jokers) or (self.area == G.consumeables)) and {x=x_off - 0.4,y=0} or
                        {x=0,y=0.65},
                    parent =self}
            }
        elseif self.children.use_button then
            self.children.use_button:remove()
            self.children.use_button = nil
        end
    end
    if self.ability.consumeable or self.ability.set == 'Joker' then
        if not self.highlighted and self.area and self.area.config.type == 'joker' and
            (#G.jokers.cards >= G.jokers.config.card_limit or (self.edition and self.edition.negative)) then
                if G.shop_jokers then G.shop_jokers:unhighlight_all() end
        end
    end
end

function Card:click() 
if Handy.controller.process_card_click(self) then return end
    if self.area and self.area:can_highlight(self) then
        if (self.area == G.hand) and (G.STATE == G.STATES.HAND_PLAYED) then return end
        if self.highlighted ~= true then 
            self.area:add_to_highlighted(self)
        else
            self.area:remove_from_highlighted(self)
            play_sound('cardSlide2', nil, 0.3)
        end
    end
    if self.area and self.area == G.deck and self.area.cards[1] == self then 
        G.FUNCS.deck_info()
    end
end

function Card:save()
    cardTable = {
        sort_id = self.sort_id,
        save_fields = {
            center = self.config.center_key,
            card = self.config.card_key,
        },
        params = self.params,
        no_ui = self.no_ui,
        base_cost = self.base_cost,
        extra_cost = self.extra_cost,
        cost = self.cost,
        sell_cost = self.sell_cost,
        facing = self.facing,
        sprite_facing = self.facing,
        flipping = nil,
        highlighted = self.highligted,
        debuff = self.debuff,
        rank = self.rank,
        added_to_deck = self.added_to_deck,
        joker_added_to_deck_but_debuffed = self.joker_added_to_deck_but_debuffed,
        label = self.label,
        playing_card = self.playing_card,
        base = self.base,
        shop_voucher = self.shop_voucher,
        shop_voucher = self.shop_voucher,
        shop_cry_bonusvoucher = self.shop_cry_bonusvoucher,
        ability = self.ability,
        pinned = self.pinned,
        edition = self.edition,
        seal = self.seal,
        bypass_discovery_center = self.bypass_discovery_center,
        bypass_discovery_ui = self.bypass_discovery_ui,
        bypass_lock = self.bypass_lock,
        unique_val = self.unique_val,
        unique_val__saved_ID = self.ID,
        ignore_base_shader = self.ignore_base_shader,
        ignore_shadow = self.ignore_shadow,
    }
    return cardTable
end

function Card:load(cardTable, other_card)
    local scale = 1
    self.config = {}
    self.config.center_key = cardTable.save_fields.center
    self.config.center = G.P_CENTERS[self.config.center_key]
    self.params = cardTable.params
    self.sticker_run = nil

    local H = G.CARD_H
    local W = G.CARD_W
    local obj = self.config.center
    if obj.load and type(obj.load) == 'function' then
        obj:load(self, cardTable, other_card)
    elseif self.config.center.name == "Half Joker" then
        self.T.h = H*scale/1.7*scale
        self.T.w = W*scale
    elseif self.config.center.name == "Wee Joker" then 
        self.T.h = H*scale*0.7*scale
        self.T.w = W*scale*0.7*scale
    elseif self.config.center.name == "Photograph" then 
        self.T.h = H*scale/1.2*scale
        self.T.w = W*scale
    elseif self.config.center.name == "Square Joker" then
        H = W 
        self.T.h = H*scale
        self.T.w = W*scale
    elseif self.config.center.set == 'Booster' then 
        self.T.h = H*1.27
        self.T.w = W*1.27
    else
        self.T.h = H*scale
        self.T.w = W*scale
    end
    if self.config.center.display_size and self.config.center.display_size.h then
        self.T.h = H*(self.config.center.display_size.h/95)
    elseif self.config.center.pixel_size and self.config.center.pixel_size.h then
        self.T.h = H*(self.config.center.pixel_size.h/95)
    end
    if self.config.center.display_size and self.config.center.display_size.w then
        self.T.w = W*(self.config.center.display_size.w/71)
    elseif self.config.center.pixel_size and self.config.center.pixel_size.w then
        self.T.w = W*(self.config.center.pixel_size.w/71)
    end
    if not self.originalsize then self.originalsize = {self.T.w, self.T.h} end
    if cardTable.edition and cardTable.edition.jen_wee then
    	self.T.w = self.T.w / Jen.config.wee_sizemod
    	self.T.h = self.T.h / Jen.config.wee_sizemod
    elseif cardTable.edition and cardTable.edition.jen_jumbo then
    	self.T.w = self.T.w * Jen.config.wee_sizemod
    	self.T.h = self.T.h * Jen.config.wee_sizemod
    end
    self.VT.h = self.T.h
    self.VT.w = self.T.w

    self.config.card_key = cardTable.save_fields.card
    self.config.card = G.P_CARDS[self.config.card_key]

    self.no_ui = cardTable.no_ui
    self.base_cost = cardTable.base_cost
    self.extra_cost = cardTable.extra_cost
    self.cost = cardTable.cost
    self.sell_cost = cardTable.sell_cost
    self.facing = cardTable.facing
    self.sprite_facing = cardTable.sprite_facing
    self.flipping = cardTable.flipping
    self.highlighted = cardTable.highlighted
    self.debuff = cardTable.debuff
    self.rank = cardTable.rank
    self.added_to_deck = cardTable.added_to_deck
    self.label = cardTable.label
    self.playing_card = cardTable.playing_card
    self.base = cardTable.base
    self.sort_id = cardTable.sort_id
    self.bypass_discovery_center = cardTable.bypass_discovery_center
    self.bypass_discovery_ui = cardTable.bypass_discovery_ui
    self.bypass_lock = cardTable.bypass_lock
    self.unique_val = cardTable.unique_val or self.unique_val
    if cardTable.unique_val__saved_ID and G.ID <= cardTable.unique_val__saved_ID then
        G.ID = cardTable.unique_val__saved_ID + 1
    end
    
    self.ignore_base_shader = cardTable.ignore_base_shader or {}
    self.ignore_shadow = cardTable.ignore_shadow or {}

    self.shop_voucher = cardTable.shop_voucher
    self.shop_voucher = cardTable.shop_voucher
    self.shop_cry_bonusvoucher = cardTable.shop_cry_bonusvoucher
    self.ability = cardTable.ability
    self.pinned = cardTable.pinned
    self.edition = cardTable.edition
    self.seal = cardTable.seal

    remove_all(self.children)
    self.children = {}
    self.children.shadow = Moveable(0, 0, 0, 0)

    self:set_sprites(self.config.center, self.config.card)
end

function Card:remove()
    self.removed = true

    if self.area then self.area:remove_card(self) end

    self:remove_from_deck()
    if self.ability.joker_added_to_deck_but_debuffed then
        if self.edition and self.edition.card_limit then
            if self.ability.consumeable then
                G.consumeables.config.card_limit = G.consumeables.config.card_limit - self.edition.card_limit
            elseif self.ability.set == 'Joker' then
                G.jokers.config.card_limit = G.jokers.config.card_limit - self.edition.card_limit
            end
        end 
    end

    if not G.OVERLAY_MENU then
        if not next(SMODS.find_card(self.config.center.key, true)) then
            G.GAME.used_jokers[self.config.center.key] = nil
        end
    end

    if G.playing_cards then
        for k, v in ipairs(G.playing_cards) do
            if v == self then
                table.remove(G.playing_cards, k)
                break
            end
        end
        for k, v in ipairs(G.playing_cards) do
            v.playing_card = k
        end
    end

    remove_all(self.children)

    for k, v in pairs(G.I.CARD) do
        if v == self then
            table.remove(G.I.CARD, k)
        end
    end
    Moveable.remove(self)
end
