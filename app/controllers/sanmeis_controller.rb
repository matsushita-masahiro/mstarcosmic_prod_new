class SanmeisController < ApplicationController
    
    layout 'main/main'
    
    before_action :authenticate_admin_user?, only: [:menu, :meishiki, :handred_hyou, :handred_graph, :koudo_area, :rikushin]
    
    def menu
    end
    
    def meishiki
    end
    
    def energy
    end
    
    def handred_hyou
    end
    
    def handred_graph
    end
    
    def koudo_area
    end
    
    def rikushin
    end
    
end
