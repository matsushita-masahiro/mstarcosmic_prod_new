# カルテ管理一覧（/karte/users）のヘッダーのソートリンクとページングリンク。
module Karte
  module UsersHelper
    ARROWS = { "asc" => "▲", "desc" => "▼" }.freeze
    # 並べ替えできることは示したいが、今の並び順と紛らわしくならないよう薄く出す
    INACTIVE_ARROW = "↕"

    # 検索語と並び順を URL に引き継ぐ。ページ送りとヘッダーの両方から使い、
    # どちらか片方だけ条件が落ちることがないようにする。
    def karte_list_params(overrides = {})
      { q: @q.presence, sort: @sort, direction: @direction }.merge(overrides).compact
    end

    # 一覧ヘッダーのソートリンク。
    # 今並べている列をもう一度押したら向きを反転し、別の列なら
    # その列の初回の向き（コントローラの FIRST_DIRECTION）で並べる。
    # ページは 1 に戻す。並べ替えると同じ 5 ページ目でも中身が別人になるため、
    # そのページ番号を持ち回っても意味がない。
    def karte_sort_link(label, key)
      active = @sort == key
      direction =
        if active
          @direction == "asc" ? "desc" : "asc"
        else
          Karte::UsersController::FIRST_DIRECTION.fetch(key)
        end

      arrow = active ? ARROWS.fetch(@direction) : INACTIVE_ARROW

      link_to karte_users_path(karte_list_params(sort: key, direction: direction, page: nil)),
              style: "color:#374151;text-decoration:none;cursor:pointer;white-space:nowrap;" do
        safe_join([
          label,
          tag.span(arrow, style: "margin-left:4px;font-size:11px;" \
                                 "color:#{active ? '#111827' : '#9ca3af'};")
        ])
      end
    end
  end
end
