let currentEntityId = null;

function createFloatingText(x, y, text, type = 'damage') {
    const floatingText = document.createElement('div');
    
    if (type === 'damage') {
        const isCritical = parseInt(text) > 20;
        floatingText.className = `floating-damage ${isCritical ? 'crit' : 'normal'}`;
        floatingText.textContent = `-${text}`;
    } else if (type === 'player-damage') {
        floatingText.className = 'floating-damage player';
        floatingText.textContent = `-${text}`;
    } else if (type === 'xp') {
        floatingText.className = 'floating-xp';
        floatingText.textContent = `+${text} xp`;
    }
    
    const randomX = (Math.random() - 0.5) * 50;
    floatingText.style.left = `${x + randomX}px`;
    floatingText.style.top = `${y}px`;
    
    document.body.appendChild(floatingText);
    
    setTimeout(() => {
        floatingText.remove();
    }, 1000);
}

function updateHealthBarColor(healthBar, percentage) {
    const healthBarInner = healthBar.querySelector('.health-bar-inner');
    
    const r = percentage < 50 ? 255 : Math.floor(255 - (percentage - 50) * 5.1);
    const g = percentage > 50 ? 189 : Math.floor(percentage * 3.78);
    
    const color = `rgb(${r}, ${g}, ${percentage < 50 ? 59 : 106})`;
    healthBarInner.style.backgroundColor = color;
    healthBarInner.style.boxShadow = `0 0 10px ${color}`;
}

function hideHealthBar(entityId) {
    let healthBar = document.getElementById("healthBar" + entityId);
    if (healthBar) {
        healthBar.style.display = "none";
        healthBar.remove();
    }
    if (currentEntityId === entityId) {
        currentEntityId = null;
    }
}

window.addEventListener('message', function(event) {
    var data = event.data;
    if (data.type === 'updateHealthBar') {
        let entityId = data.entityId;

        if (currentEntityId !== entityId) {
            hideHealthBar(currentEntityId);
        }

        let healthBar = document.getElementById("healthBar" + entityId);

        if (!healthBar) {
            let newHealthBar = `
                <div class="health-bar" id="healthBar${entityId}">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="health-bar-icon">
                        <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/>
                    </svg>
                    <div class="health-bar-text" id="healthBarText${entityId}">Health</div>
                    <div class="health-bar-inner" id="healthBarInner${entityId}"></div>
                </div>
            `;
            $('.wrapper').append(newHealthBar);
            healthBar = document.getElementById("healthBar" + entityId);
        }

        healthBar.style.left = data.x + "px";
        healthBar.style.top = data.y + "px";
        healthBar.style.display = "block";

        let healthBarInner = document.getElementById("healthBarInner" + entityId);
        let healthPercentage = (data.currentHealth / data.maxHealth) * 100;
        healthBarInner.style.width = healthPercentage + "%";
        
        updateHealthBarColor(healthBar, healthPercentage);

        let healthBarText = document.getElementById("healthBarText" + entityId);
        healthBarText.textContent = `${Math.floor(data.currentHealth)} / ${Math.floor(data.maxHealth)}`;

        if (data.previousHealth && data.currentHealth < data.previousHealth) {
            const damage = data.previousHealth - data.currentHealth;
            createFloatingText(data.x, data.y - 50, Math.floor(damage), 'damage');
        }

        currentEntityId = entityId;
    } else if (data.type === 'showPlayerDamage') {
        createFloatingText(data.x, data.y - 50, Math.floor(data.damage), 'player-damage');
    } else if (data.type === 'showXP') {
        createFloatingText(data.x, data.y - 50, data.amount, 'xp');
    } else if (data.type === 'hideHealthBar') {
        let entityId = data.entityId;
        hideHealthBar(entityId);
    }
});