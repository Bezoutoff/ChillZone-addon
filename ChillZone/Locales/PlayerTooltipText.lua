local _, ns = ...
local L = ns.L
L.PLAYER_TOOLTIP_SETTINGS = "Player tooltips"
L.PLAYER_TOOLTIP_DESC = "Keep the game's tooltip and add ChillZone guild ranks in a compact, readable line."
L.PLAYER_TOOLTIP_DETAILS = "Show ChillZone player details"
L.PLAYER_TOOLTIP_COLORS = "Use class colors for guild ranks"
L.PLAYER_TOOLTIP_SIZE = "Tooltip size: %d%%"
L.PLAYER_TOOLTIP_NEXT = "Changes apply on the next hover. These additions pause with gamepad UI or in combat."
if GetLocale() == "ptBR" then
	L.PLAYER_TOOLTIP_SETTINGS = "Dicas de jogadores"
	L.PLAYER_TOOLTIP_DESC = "Mantenha a dica do jogo e acrescente o posto na guilda ChillZone em uma linha compacta."
	L.PLAYER_TOOLTIP_DETAILS = "Mostrar detalhes dos jogadores ChillZone"
	L.PLAYER_TOOLTIP_COLORS = "Usar cores de classe nos postos da guilda"
	L.PLAYER_TOOLTIP_SIZE = "Tamanho da dica: %d%%"
	L.PLAYER_TOOLTIP_NEXT = "As mudanças valem ao passar o mouse novamente. Estes detalhes ficam pausados com controle ou em combate."
end
