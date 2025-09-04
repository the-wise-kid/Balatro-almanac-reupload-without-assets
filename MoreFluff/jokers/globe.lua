local joker = {
  name = "Globe",
  config = {
    extra = 1
  },
  pos = {x = 7, y = 0},
  rarity = 2,
  cost = 6,
  unlocked = true,
  discovered = true,
  blueprint_compat = true,
  eternal_compat = true,
  perishable_compat = true,
  loc_txt = {
    name = "Globe",
    text = {
      "Create #1# {C:planet}Planet{} card",
      "when you {C:attention}reroll{} in the shop",
    }
  },
  loc_vars = function(self, info_queue, center)
    return {
      vars = { center.ability.extra }
    }
  end,
  calculate = function(self, card, context)
    if context.reroll_shop and #G.consumeables.cards + G.GAME.consumeable_buffer < G.consumeables.config.card_limit then
local jokers_to_create = math.floor(math.min(card.ability.extra, G.consumeables.config.card_limit - (#G.consumeables.cards + G.GAME.consumeable_buffer)))      
for i = 1,jokers_to_create do
      G.GAME.consumeable_buffer = G.GAME.consumeable_buffer + 1
      G.E_MANAGER:add_event(Event({
          trigger = 'before',
          delay = 0.0,
          func = (function()
                  local card = create_card('Planet',G.consumeables, nil, nil, nil, nil, nil, '8ba')
                  card:add_to_deck()
                  G.consumeables:emplace(card)
                  G.GAME.consumeable_buffer = 0
              return true
          end)}))
            end
        return {
                  message = localize('k_plus_planet'),
                  colour = G.C.SECONDARY_SET.Planet,
                  card = card
              }
    end
  end
}

if JokerDisplay then
  JokerDisplay.Definitions["j_mf_globe"] = {
    text = {
      { ref_table = "card.joker_display_values", ref_value = "planet", retrigger_type = "mult" },
    },
    reminder_text = {
      { ref_table = "card.joker_display_values", ref_value = "reminder_text", color = G.C.INACTIVE },
    },
    calc_function = function(card)
      card.joker_display_values.reminder_text = localize("k_display_on_reroll")
      card.joker_display_values.planet = localize("k_plus_planet")
    end,
  }
end

return joker
